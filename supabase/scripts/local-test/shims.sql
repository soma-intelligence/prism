-- Stand-ins for what a hosted Supabase project already has, so the migrations
-- and tests run on a plain Postgres 17. Never applied to a real project.

-- Roles belong to the cluster, so the second test database finds them made.
do $$
begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
    if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin bypassrls; end if;
end;
$$;
grant usage on schema public to anon, authenticated, service_role;

-- auth: the users table the profiles trigger hangs on, and auth.uid() read
-- from the request's JWT claims, the way Supabase sets them.
create schema auth;
grant usage on schema auth to anon, authenticated, service_role;
create table auth.users (
    id uuid primary key,
    email text,
    raw_user_meta_data jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
);
create function auth.jwt() returns jsonb language sql stable as $$
    select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
$$;
create function auth.uid() returns uuid language sql stable as $$
    select nullif(auth.jwt() ->> 'sub', '')::uuid
$$;
grant execute on function auth.jwt(), auth.uid() to anon, authenticated, service_role;

-- storage: buckets, objects with row level security, and foldername().
create schema storage;
grant usage on schema storage to anon, authenticated, service_role;
create table storage.buckets (
    id text primary key,
    name text not null,
    public boolean default false,
    file_size_limit bigint,
    allowed_mime_types text[]
);
create table storage.objects (
    id uuid primary key default gen_random_uuid(),
    bucket_id text references storage.buckets (id),
    name text not null,
    owner uuid default auth.uid(),
    created_at timestamptz default now(),
    unique (bucket_id, name)
);
alter table storage.objects enable row level security;
grant select, insert, update, delete on storage.objects to anon, authenticated;
grant all on storage.objects, storage.buckets to service_role;
grant select on storage.buckets to anon, authenticated;
create function storage.foldername(name text) returns text[] language sql immutable as $$
    select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1]
$$;
grant execute on function storage.foldername(text) to anon, authenticated, service_role;

-- pg_cron, pg_net and Vault, as much as the migrations call.
create schema cron;
create table cron.job (jobid serial primary key, jobname text unique, schedule text, command text);
create function cron.schedule(n text, s text, c text) returns bigint language sql as $$
    insert into cron.job (jobname, schedule, command) values (n, s, c)
    on conflict (jobname) do update set schedule = excluded.schedule, command = excluded.command
    returning jobid
$$;
create schema net;
create table net.calls (id bigserial primary key, url text, headers jsonb, body jsonb, timeout int);
create function net.http_post(url text, body jsonb default '{}', params jsonb default '{}', headers jsonb default '{}', timeout_milliseconds int default 5000)
returns bigint language sql as $$
    insert into net.calls (url, headers, body, timeout) values (url, headers, body, timeout_milliseconds) returning id
$$;
create schema vault;
create table vault.secrets (name text, decrypted_secret text);
create view vault.decrypted_secrets as select * from vault.secrets;

-- The migrations' "create extension pg_cron" and "pg_net" lines are dropped
-- by run.sh; the schemas above stand in for both.
