-- app_articles: the general wellness library the Prism app shows on Pulse > Explore.
-- Written in the Supabase dashboard (Table Editor) or by script with the service role,
-- read by the app with the publishable (anon) key. The public sees a row once it is
-- published and its date has passed. Not applied by anything here: run it yourself.
--
-- Lives in the app's project, not the website's: the website's
-- blog (public.posts) is a different database. The app needs a topic, a reading time,
-- a cover and a source list per article, and its pieces are general reading that never
-- mentions Soma's hardware.

create table public.app_articles (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique
    constraint app_articles_slug_format check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and char_length(slug) <= 100),
  title text not null
    constraint app_articles_title_length check (char_length(btrim(title)) between 1 and 120),
  subtitle text not null default ''
    constraint app_articles_subtitle_length check (char_length(subtitle) <= 160),
  topic text not null
    constraint app_articles_topic check (topic in ('sleep', 'heart', 'recovery', 'movement', 'nutrition', 'mind', 'longevity')),
  minutes smallint not null default 3
    constraint app_articles_minutes_range check (minutes between 1 and 60),
  cover_image_url text
    constraint app_articles_cover_https check (cover_image_url is null or cover_image_url ~ '^https://'),
  -- The photographer, shown under the cover as "Photo: Name, Unsplash", and the photo's page.
  cover_credit text,
  cover_credit_url text
    constraint app_articles_credit_https check (cover_credit_url is null or cover_credit_url ~ '^https://'),
  body text not null default '',
  -- [{"title": "...", "publisher": "Journal, 2024", "url": "https://doi.org/..."}]
  sources jsonb not null default '[]'::jsonb
    constraint app_articles_sources_array check (jsonb_typeof(sources) = 'array'),
  published boolean not null default false,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint app_articles_published_has_date check (not published or published_at is not null)
);

comment on table public.app_articles is
  'Prism app Explore library. body is Markdown (## headings, paragraphs, - lists, inline emphasis and links). Public once published is true and published_at has passed. General wellness only: no Soma hardware, no diagnosis or treatment claims.';

create index app_articles_published_idx on public.app_articles (published_at desc) where published;

-- Keeps updated_at current, and dates a row the moment it is published without a date.
create function public.app_articles_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  if new.published and new.published_at is null then
    new.published_at := now();
  end if;
  return new;
end;
$$;

revoke execute on function public.app_articles_before_write() from public, anon, authenticated;

create trigger app_articles_before_write
before insert or update on public.app_articles
for each row execute function public.app_articles_before_write();

alter table public.app_articles enable row level security;

create policy "app articles are public once published"
on public.app_articles for select
to anon, authenticated
using (published and published_at <= now());

-- Least privilege: read for the app's roles, everything for the service role. Grants
-- are explicit, whatever default privileges the project hands out on a new table.
revoke all on public.app_articles from anon, authenticated;
grant select on public.app_articles to anon, authenticated;
grant select, insert, update, delete on public.app_articles to service_role;
