-- Open Health Sync: which user on the Open Health Sync instance holds each
-- account's connected wearables (Oura, Whoop, Withings, Garmin and the rest).
--
-- The `ohs` Edge Function writes the row the first time a person connects a
-- provider, with the service role, and reads it on every call. The instance's
-- tenant key never leaves that function. A person may read their own row and
-- write none; deleting the account cascades here, after `delete-account` has
-- deleted the user on the instance.

create table public.ohs_links (
    user_id uuid primary key references auth.users (id) on delete cascade,
    ohs_user_id uuid not null unique,
    created_at timestamptz not null default now()
);

alter table public.ohs_links enable row level security;

revoke all on public.ohs_links from anon, authenticated;
grant select on public.ohs_links to authenticated;
grant all on public.ohs_links to service_role;

create policy ohs_links_read_own on public.ohs_links
    for select to authenticated
    using (user_id = (select auth.uid()));
