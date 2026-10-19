-- Explore articles written by a model from the week's news (Edge Function
-- articles-generate), kept apart from the ones written by hand.
--
-- A generated row says so: generated_by names the function, model the Foundry
-- deployment, source_news_ids the news_items it was written from. It lands
-- with published = false unless the function runs with ARTICLES_AUTO_PUBLISH
-- set, so the owner reads it before anyone else does. The app shows a
-- generated article with a line saying it was written automatically.
--
-- Daily at 05:23 UTC pg_cron has pg_net call the function with the service
-- role key from Vault, the same way news_ingest_tick does.

alter table public.app_articles
    add column generated_by text
        constraint app_articles_generated_by_known check (generated_by is null or generated_by in ('articles-generate')),
    add column model text
        constraint app_articles_model_length check (model is null or char_length(model) between 1 and 100),
    add column source_news_ids uuid[] not null default '{}',
    add constraint app_articles_generated_has_model check (generated_by is null or model is not null);

comment on column public.app_articles.generated_by is 'Null for an article written by hand; articles-generate for one a model wrote from news_items.';
comment on column public.app_articles.source_news_ids is 'The news_items a generated article was written from; its sources list names them.';

create index app_articles_generated_idx on public.app_articles (generated_by, created_at desc) where generated_by is not null;

create function public.articles_generate_tick()
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
    raise warning 'articles_generate_tick: no service_role_key in Vault, skipped';
    return;
  end if;
  -- The project address is a Vault secret too, so the key below only ever goes to the
  -- project that holds it. Store it once: select vault.create_secret(
  -- 'https://<your-ref>.supabase.co', 'project_url', 'base address of this project');
  select decrypted_secret into base from vault.decrypted_secrets where name = 'project_url';
  if base is null then
    raise warning 'articles_generate_tick: no project_url in Vault, skipped';
    return;
  end if;
  perform net.http_post(
    url := rtrim(base, '/') || '/functions/v1/articles-generate',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || token),
    body := jsonb_build_object('trigger', 'cron'),
    timeout_milliseconds := 10000
  );
end;
$$;

revoke execute on function public.articles_generate_tick() from public, anon, authenticated;
grant execute on function public.articles_generate_tick() to service_role;

select cron.schedule('articles-generate', '23 5 * * *', $$select public.articles_generate_tick()$$);
