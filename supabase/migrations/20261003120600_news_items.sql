-- news_items: health and wellness news for the Prism app (Pulse > Explore). Every six hours
-- pg_cron has pg_net call the Edge Function news-ingest (functions/news-ingest), which reads a
-- curated list of RSS and Atom feeds, has a chat model on Azure AI Foundry write a short neutral
-- summary of each new item, and stores one row per item with the service role. A row holds the
-- headline, the link, our own summary, an image URL and the source's name: never the article's
-- text. The app reads rows from the last 60 days with the publishable (anon) key.
--
-- The call carries the service role key, kept in Vault as `service_role_key` rather than in the
-- job's text. Without it the
-- call is skipped with a warning and nothing else changes. The request leaves after the commit
-- and the function answers at once (it works in the background), so pg_net's wait stays short.
-- Requires pg_cron and pg_net (20261003115900_extensions).
-- Belongs to the app's project, not the website's.
-- Not applied by anything here: run it yourself (supabase/README.md, "News and generated articles").

create table public.news_items (
  id uuid primary key default gen_random_uuid(),
  source_name text not null
    constraint news_items_source_name_length check (char_length(btrim(source_name)) between 1 and 80),
  source_url text not null unique
    constraint news_items_source_url_https check (source_url ~ '^https://' and char_length(source_url) <= 2000),
  title text not null
    constraint news_items_title_length check (char_length(btrim(title)) between 1 and 300),
  summary text not null
    constraint news_items_summary_length check (char_length(btrim(summary)) between 40 and 1200),
  topics text[] not null
    constraint news_items_topics_known check (
      cardinality(topics) between 1 and 3
      and topics <@ array['sleep', 'heart', 'recovery', 'movement', 'nutrition', 'mind', 'longevity', 'research']::text[]
    ),
  image_url text
    constraint news_items_image_https check (image_url is null or (image_url ~ '^https://' and char_length(image_url) <= 2000)),
  published_at timestamptz not null,
  model text not null
    constraint news_items_model_length check (char_length(model) between 1 and 100),
  created_at timestamptz not null default now()
);

comment on table public.news_items is
  'Health and wellness news for the app: headline, link, our own 2 to 3 sentence summary, topics, image URL and source name, written by the Edge Function news-ingest. Never the article text. Public for 60 days after publication.';
comment on column public.news_items.summary is
  'Written by the model named in model, from the feed''s own excerpt only. Not the source''s text.';
comment on column public.news_items.image_url is
  'Hotlinked from the source (og:image or the feed''s media), only for sources whose terms allow it. Null otherwise.';

-- The app's query: newest first, optionally by topic.
create index news_items_published_at_idx on public.news_items (published_at desc);
create index news_items_topics_idx on public.news_items using gin (topics);

alter table public.news_items enable row level security;

create policy "news items are public for 60 days"
on public.news_items for select
to anon, authenticated
using (published_at > now() - interval '60 days');

-- New tables are not exposed to the Data API by default (Supabase, 2026-04-28): grant what
-- each role needs, nothing more. Writes go through the service role only.
revoke all on public.news_items from anon, authenticated;
grant select on public.news_items to anon, authenticated;
grant select, insert, update, delete on public.news_items to service_role;

-- Run by pg_cron every six hours. pg_net posts to the function with the service role key from
-- Vault. The function checks that bearer itself, starts the run in the background and answers
-- 202 within a second or two, so 10 seconds is plenty.
create function public.news_ingest_tick()
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  token text;
  base text;
begin
  select decrypted_secret into token from vault.decrypted_secrets where name = 'service_role_key';
  if token is null then
    raise warning 'news_ingest_tick: no service_role_key in Vault, skipped';
    return;
  end if;
  -- The project address is a Vault secret too, so the key below only ever goes to the
  -- project that holds it. Store it once: select vault.create_secret(
  -- 'https://<your-ref>.supabase.co', 'project_url', 'base address of this project');
  select decrypted_secret into base from vault.decrypted_secrets where name = 'project_url';
  if base is null then
    raise warning 'news_ingest_tick: no project_url in Vault, skipped';
    return;
  end if;
  perform net.http_post(
    url := rtrim(base, '/') || '/functions/v1/news-ingest',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || token),
    body := jsonb_build_object('trigger', 'cron'),
    timeout_milliseconds := 10000
  );
end;
$$;

revoke execute on function public.news_ingest_tick() from public, anon, authenticated;
grant execute on function public.news_ingest_tick() to service_role;

-- At 00:13, 06:13, 12:13 and 18:13 UTC. pg_cron runs the job as the role that made it, which
-- owns the function.
select cron.schedule(
  'news-ingest',
  '13 */6 * * *',
  $$select public.news_ingest_tick()$$
);

-- Retention, daily at 03:37 UTC: the app never shows a row after 60 days, so rows go after 180
-- (kept that long only so a dropped item is not fetched and summarized again while a feed
-- still lists it).
select cron.schedule(
  'news-items-retention',
  '37 3 * * *',
  $$delete from public.news_items where published_at < now() - interval '180 days'$$
);
