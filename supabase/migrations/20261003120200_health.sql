-- Apple Health in the cloud: every sample the person allowed, a daily roll up,
-- and how far each phone's upload has gone.
--
-- The app (HealthCloud.HealthSampleUploader in WellnessKit) reads Health with
-- anchored queries and upserts health_samples on (user_id, hk_uuid), so a
-- page sent twice is stored once. Deleted Health samples are deleted here by
-- hk_uuid. health_daily is written by the app from Health's own statistics,
-- which remove the overlap between a watch and a phone that a plain sum over
-- health_samples would count twice.
--
-- Row level security: owner only. The service role has every privilege.

-- health_samples ----------------------------------------------------------------

create table public.health_samples (
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    -- HealthKit's HKObject.uuid: stable for the life of the sample.
    hk_uuid uuid not null,
    -- The HealthKit identifier, verbatim: HKQuantityTypeIdentifierHeartRate.
    metric text not null
        constraint health_samples_metric_length check (char_length(metric) between 1 and 120),
    kind text not null
        constraint health_samples_kind_known check (kind in ('quantity', 'category', 'workout')),
    -- In the metric's canonical unit; a category's coded value; a workout's activity type.
    value double precision not null,
    -- HealthExportCore.HealthUnit raw value: count, countPerMinute, kilogram, none...
    unit text not null,
    start_at timestamptz not null,
    end_at timestamptz not null,
    source_name text,
    source_bundle text,
    device_name text,
    device_model text,
    was_user_entered boolean not null default false,
    inserted_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary key (user_id, hk_uuid),
    constraint health_samples_ordered check (end_at >= start_at)
);

comment on table public.health_samples is
    'Every Apple Health sample the person allowed, one row per HealthKit object, with its provenance (source app, device, typed in or measured). Upserted by the app on (user_id, hk_uuid); a sample deleted in Health is deleted here. Sensitive metrics (cycle tracking and the like) are not uploaded by default.';
comment on column public.health_samples.value is 'Quantity in the canonical unit; category coded value; workout HKWorkoutActivityType raw value.';

-- The read path: one person, one metric, a time range, newest first.
create index health_samples_user_metric_start_idx on public.health_samples (user_id, metric, start_at desc);

create trigger health_samples_touch_updated_at
before update on public.health_samples
for each row execute function public.touch_updated_at();

alter table public.health_samples enable row level security;

create policy health_samples_select_own on public.health_samples
for select to authenticated using (user_id = (select auth.uid()));
create policy health_samples_insert_own on public.health_samples
for insert to authenticated with check (user_id = (select auth.uid()));
create policy health_samples_update_own on public.health_samples
for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy health_samples_delete_own on public.health_samples
for delete to authenticated using (user_id = (select auth.uid()));

revoke all on public.health_samples from anon, authenticated;
grant select, insert, update, delete on public.health_samples to authenticated;
grant all on public.health_samples to service_role;

-- health_daily ------------------------------------------------------------------

create table public.health_daily (
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    metric text not null,
    -- The person's local day, in time_zone.
    day date not null,
    time_zone text not null,
    unit text not null,
    -- Cumulative quantities: Health's deduplicated total. Categories and
    -- workouts: seconds covered inside the day.
    sum double precision,
    -- Discrete quantities: mean, lowest, highest.
    avg double precision,
    min double precision,
    max double precision,
    count integer
        constraint health_daily_count_positive check (count is null or count >= 0),
    computed_at timestamptz not null default now(),
    primary key (user_id, metric, day)
);

comment on table public.health_daily is
    'One row per metric per local day, written by the app from Health statistics after each upload: sum for cumulative quantities (deduplicated by Health), avg/min/max/count for discrete ones, count and seconds for categories and workouts.';

create index health_daily_user_day_idx on public.health_daily (user_id, day desc);

create or replace function public.health_daily_touch()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.computed_at := now();
    return new;
end;
$$;

revoke execute on function public.health_daily_touch() from public, anon, authenticated;

create trigger health_daily_touch
before insert or update on public.health_daily
for each row execute function public.health_daily_touch();

alter table public.health_daily enable row level security;

create policy health_daily_select_own on public.health_daily
for select to authenticated using (user_id = (select auth.uid()));
create policy health_daily_insert_own on public.health_daily
for insert to authenticated with check (user_id = (select auth.uid()));
create policy health_daily_update_own on public.health_daily
for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy health_daily_delete_own on public.health_daily
for delete to authenticated using (user_id = (select auth.uid()));

revoke all on public.health_daily from anon, authenticated;
grant select, insert, update, delete on public.health_daily to authenticated;
grant all on public.health_daily to service_role;

-- health_sync_state -------------------------------------------------------------

create table public.health_sync_state (
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    -- devices.installation_id: an anchor belongs to one phone's Health store.
    installation_id text not null,
    metric text not null,
    -- The HKQueryAnchor keyed archive, base64. Lets a reinstall resume.
    anchor text,
    last_synced_at timestamptz not null default now(),
    samples_uploaded bigint not null default 0,
    last_sample_end timestamptz,
    last_error text,
    primary key (user_id, installation_id, metric)
);

comment on table public.health_sync_state is
    'How far each installation has uploaded each Health metric: the anchor after the last confirmed page, when, how many samples so far, and the newest sample end. Written by the app after each metric.';

alter table public.health_sync_state enable row level security;

create policy health_sync_state_select_own on public.health_sync_state
for select to authenticated using (user_id = (select auth.uid()));
create policy health_sync_state_insert_own on public.health_sync_state
for insert to authenticated with check (user_id = (select auth.uid()));
create policy health_sync_state_update_own on public.health_sync_state
for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy health_sync_state_delete_own on public.health_sync_state
for delete to authenticated using (user_id = (select auth.uid()));

revoke all on public.health_sync_state from anon, authenticated;
grant select, insert, update, delete on public.health_sync_state to authenticated;
grant all on public.health_sync_state to service_role;
