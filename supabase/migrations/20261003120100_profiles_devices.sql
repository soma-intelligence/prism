-- The person and their phones.
--
-- profiles: one row per account, id = auth.users.id, made by a trigger the
-- moment Supabase Auth creates the user (Sign in with Apple included), so the
-- app can always update rather than guess whether to insert.
-- devices: one row per installation, for push tokens later and to tell two
-- phones' Health anchors apart.
--
-- Row level security: a person reads and writes only their own rows. The
-- service role has every privilege and bypasses row level security.

-- Shared trigger: keeps updated_at current on every write.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

revoke execute on function public.touch_updated_at() from public, anon, authenticated;

-- profiles --------------------------------------------------------------------

create table public.profiles (
    id uuid primary key references auth.users (id) on delete cascade,
    first_name text
        constraint profiles_first_name_length check (first_name is null or char_length(first_name) <= 80),
    birth_date date
        constraint profiles_birth_date_range check (birth_date is null or birth_date >= date '1900-01-01'),
    sex text
        constraint profiles_sex_known check (sex is null or sex in ('male', 'female', 'other')),
    height_cm numeric(5, 1)
        constraint profiles_height_range check (height_cm is null or height_cm between 40 and 280),
    units text not null default 'metric'
        constraint profiles_units_known check (units in ('metric', 'imperial')),
    focus text[] not null default '{}',
    chronotype jsonb
        constraint profiles_chronotype_object check (chronotype is null or jsonb_typeof(chronotype) = 'object'),
    time_zone text,
    -- Path inside the private avatars bucket, always '<id>/avatar.jpg' when set.
    avatar_path text
        constraint profiles_avatar_in_own_folder check (avatar_path is null or avatar_path = id::text || '/avatar.jpg'),
    avatar_updated_at timestamptz,
    onboarded_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

comment on table public.profiles is
    'One row per account (id = auth.users.id), made by the on_auth_user_created trigger. What the person told Soma about themselves: first name, birth date, sex, height, units, focus areas, chronotype answers. The photo lives in the private avatars bucket at avatar_path.';
comment on column public.profiles.focus is 'FocusArea raw values in the order they were picked: sleep, energy, stress, longevity, skin, routines.';
comment on column public.profiles.chronotype is 'The rMEQ answers as the app encodes RMEQAnswers, with answered_at.';

create trigger profiles_touch_updated_at
before update on public.profiles
for each row execute function public.touch_updated_at();

alter table public.profiles enable row level security;

create policy profiles_select_own on public.profiles
for select to authenticated using (id = (select auth.uid()));
create policy profiles_insert_own on public.profiles
for insert to authenticated with check (id = (select auth.uid()));
create policy profiles_update_own on public.profiles
for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

revoke all on public.profiles from anon, authenticated;
grant select, insert, update on public.profiles to authenticated;
grant all on public.profiles to service_role;

-- A profile for every new user. Apple shares a name on the first sign in
-- only, and Supabase keeps what it got in raw_user_meta_data.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
    insert into public.profiles (id, first_name)
    values (
        new.id,
        nullif(btrim(left(coalesce(
            new.raw_user_meta_data ->> 'first_name',
            new.raw_user_meta_data ->> 'given_name',
            split_part(coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', ''), ' ', 1)
        ), 80)), '')
    )
    on conflict (id) do nothing;
    return new;
end;
$$;

revoke execute on function public.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- devices ---------------------------------------------------------------------

create table public.devices (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    -- A random identifier the app makes once per installation and keeps in the Keychain.
    installation_id text not null
        constraint devices_installation_id_length check (char_length(installation_id) between 8 and 64),
    platform text not null
        constraint devices_platform_known check (platform in ('ios', 'ipados', 'macos', 'visionos', 'watchos')),
    model text,
    os_version text,
    app_version text,
    -- APNs device token, hex. Null until notifications are allowed and the push channel exists.
    push_token text,
    push_environment text
        constraint devices_push_environment_known check (push_environment is null or push_environment in ('sandbox', 'production')),
    time_zone text,
    last_seen_at timestamptz not null default now(),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint devices_one_row_per_installation unique (user_id, installation_id)
);

comment on table public.devices is
    'One row per app installation per account: platform, model, versions, and the APNs token once push exists. installation_id also keys health_sync_state, because Health anchors belong to one phone.';

create index devices_user_idx on public.devices (user_id);

create trigger devices_touch_updated_at
before update on public.devices
for each row execute function public.touch_updated_at();

alter table public.devices enable row level security;

create policy devices_select_own on public.devices
for select to authenticated using (user_id = (select auth.uid()));
create policy devices_insert_own on public.devices
for insert to authenticated with check (user_id = (select auth.uid()));
create policy devices_update_own on public.devices
for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy devices_delete_own on public.devices
for delete to authenticated using (user_id = (select auth.uid()));

revoke all on public.devices from anon, authenticated;
grant select, insert, update, delete on public.devices to authenticated;
grant all on public.devices to service_role;

-- Account deletion ------------------------------------------------------------

-- The App Store requires that an account made in the app can be deleted in
-- the app. Deleting the auth user cascades to every table here. Storage
-- objects are not rows Postgres may delete directly: the app removes the
-- person's avatars and health-uploads folders through the Storage API first.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user uuid := auth.uid();
begin
    if v_user is null then
        raise exception 'delete_my_account requires an authenticated user' using errcode = '28000';
    end if;
    delete from auth.users where id = v_user;
end;
$$;

revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
