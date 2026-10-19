-- Record sync foundation, copied from ../WellnessKit/supabase/migrations/20260916120000_sync_foundation.sql
-- (the server half of SyncCore's RemoteRecordStore contract) without its test probe table.
-- Keep the two in step: the app's record tables below are created through
-- public.sync_create_record_table and pushed and pulled through sync_push and sync_pull.

-- Record sync foundation: one revision sequence shared by every record table,
-- a registry of record types, compare-and-set push, cursor pull, and
-- tombstone expiry. The client contract is documented on RemoteRecordStore.

create sequence if not exists public.sync_revision as bigint;

create table if not exists public.sync_record_types (
    record_type text primary key check (record_type ~ '^[a-z][a-z0-9_]*$'),
    table_name text not null unique
);

create table if not exists public.sync_tombstone_horizon (
    record_type text not null references public.sync_record_types (record_type) on delete cascade,
    user_id uuid not null,
    removed_through bigint not null default 0,
    primary key (record_type, user_id)
);

alter table public.sync_record_types enable row level security;
alter table public.sync_tombstone_horizon enable row level security;

drop policy if exists sync_record_types_read on public.sync_record_types;
create policy sync_record_types_read on public.sync_record_types for select to authenticated using (true);

drop policy if exists sync_tombstone_horizon_read on public.sync_tombstone_horizon;
create policy sync_tombstone_horizon_read on public.sync_tombstone_horizon for select to authenticated using (user_id = auth.uid());

grant select on public.sync_record_types to authenticated;
grant select on public.sync_tombstone_horizon to authenticated;
grant usage on sequence public.sync_revision to authenticated;

create or replace function public.sync_assign_revision()
returns trigger
language plpgsql
as $$
begin
    new.revision := nextval('public.sync_revision');
    new.updated_at := now();
    return new;
end;
$$;

-- Creates a record table with the sync columns, its index, its trigger and its
-- row level security, then registers it. Kit migrations call this.
create or replace function public.sync_create_record_table(p_record_type text, p_table_name text)
returns void
language plpgsql
as $$
begin
    execute format($ddl$
        create table if not exists public.%I (
            id uuid primary key,
            user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
            revision bigint not null default 0,
            deleted boolean not null default false,
            payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload) = 'object'),
            updated_at timestamptz not null default now()
        )$ddl$, p_table_name);
    execute format('create index if not exists %I on public.%I (user_id, revision)', p_table_name || '_user_revision', p_table_name);
    execute format('drop trigger if exists sync_assign_revision on public.%I', p_table_name);
    execute format('create trigger sync_assign_revision before insert or update on public.%I for each row execute function public.sync_assign_revision()', p_table_name);
    execute format('alter table public.%I enable row level security', p_table_name);
    execute format('drop policy if exists sync_select on public.%I', p_table_name);
    execute format('create policy sync_select on public.%I for select to authenticated using (user_id = auth.uid())', p_table_name);
    execute format('drop policy if exists sync_insert on public.%I', p_table_name);
    execute format('create policy sync_insert on public.%I for insert to authenticated with check (user_id = auth.uid())', p_table_name);
    execute format('drop policy if exists sync_update on public.%I', p_table_name);
    execute format('create policy sync_update on public.%I for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid())', p_table_name);
    execute format('grant select, insert, update on public.%I to authenticated', p_table_name);
    insert into public.sync_record_types (record_type, table_name)
    values (p_record_type, p_table_name)
    on conflict (record_type) do update set table_name = excluded.table_name;
end;
$$;

revoke all on function public.sync_create_record_table(text, text) from public, anon, authenticated;

create or replace function public.sync_push(record_type text, changes jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
    v_table text;
    v_change jsonb;
    v_id uuid;
    v_base bigint;
    v_deleted boolean;
    v_payload jsonb;
    v_current_id uuid;
    v_current_revision bigint;
    v_current_deleted boolean;
    v_current_payload jsonb;
    v_revision bigint;
    v_results jsonb := '[]'::jsonb;
begin
    if auth.uid() is null then
        raise exception 'sync_push requires an authenticated user' using errcode = '28000';
    end if;
    select t.table_name into v_table from public.sync_record_types t where t.record_type = sync_push.record_type;
    if v_table is null then
        raise exception 'unknown record type %', sync_push.record_type using errcode = '22023';
    end if;
    if jsonb_typeof(changes) is distinct from 'array' then
        raise exception 'changes must be a JSON array' using errcode = '22023';
    end if;

    for v_change in select value from jsonb_array_elements(changes) loop
        v_id := (v_change ->> 'id')::uuid;
        v_base := (v_change ->> 'base_revision')::bigint;
        v_deleted := coalesce((v_change ->> 'deleted')::boolean, false);
        v_payload := coalesce(v_change -> 'payload', '{}'::jsonb);
        v_current_id := null;

        execute format('select id, revision, deleted, payload from public.%I where id = $1 for update', v_table)
            into v_current_id, v_current_revision, v_current_deleted, v_current_payload
            using v_id;

        if v_current_id is null then
            if v_base is not null then
                v_results := v_results || jsonb_build_array(jsonb_build_object(
                    'id', v_id, 'outcome', 'conflict',
                    'record', jsonb_build_object('id', v_id, 'revision', 0, 'deleted', true, 'payload', null)));
            else
                begin
                    execute format('insert into public.%I (id, deleted, payload) values ($1, $2, $3) returning revision', v_table)
                        into v_revision
                        using v_id, v_deleted, v_payload;
                    v_results := v_results || jsonb_build_array(jsonb_build_object('id', v_id, 'outcome', 'applied', 'revision', v_revision));
                exception when unique_violation or insufficient_privilege or check_violation then
                    v_results := v_results || jsonb_build_array(jsonb_build_object('id', v_id, 'outcome', 'rejected', 'reason', sqlerrm));
                end;
            end if;
        elsif v_current_revision = v_base then
            execute format('update public.%I set deleted = $2, payload = $3 where id = $1 returning revision', v_table)
                into v_revision
                using v_id, v_deleted, v_payload;
            v_results := v_results || jsonb_build_array(jsonb_build_object('id', v_id, 'outcome', 'applied', 'revision', v_revision));
        elsif v_current_deleted = v_deleted and v_current_payload = v_payload then
            v_results := v_results || jsonb_build_array(jsonb_build_object('id', v_id, 'outcome', 'applied', 'revision', v_current_revision));
        else
            v_results := v_results || jsonb_build_array(jsonb_build_object(
                'id', v_id, 'outcome', 'conflict',
                'record', jsonb_build_object('id', v_current_id, 'revision', v_current_revision, 'deleted', v_current_deleted, 'payload', v_current_payload)));
        end if;
    end loop;
    return v_results;
end;
$$;

grant execute on function public.sync_push(text, jsonb) to authenticated;
revoke execute on function public.sync_push(text, jsonb) from anon, public;

create or replace function public.sync_pull(record_type text, after bigint, page_limit integer, resyncing boolean default false)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
    v_table text;
    v_horizon bigint;
    v_records jsonb;
    v_last bigint;
    v_has_more boolean;
begin
    if auth.uid() is null then
        raise exception 'sync_pull requires an authenticated user' using errcode = '28000';
    end if;
    select t.table_name into v_table from public.sync_record_types t where t.record_type = sync_pull.record_type;
    if v_table is null then
        raise exception 'unknown record type %', sync_pull.record_type using errcode = '22023';
    end if;
    if page_limit is null or page_limit < 1 or page_limit > 1000 then
        raise exception 'page_limit must be between 1 and 1000' using errcode = '22023';
    end if;

    select h.removed_through into v_horizon
    from public.sync_tombstone_horizon h
    where h.record_type = sync_pull.record_type and h.user_id = auth.uid();
    -- A full resync pages from the start and prunes at the end, so its own page
    -- cursor never expires.
    if not coalesce(resyncing, false) and after is not null and after < coalesce(v_horizon, 0) then
        return jsonb_build_object('cursor_expired', true, 'records', '[]'::jsonb, 'has_more', false);
    end if;

    execute format($query$
        select
            coalesce(jsonb_agg(jsonb_build_object('id', id, 'revision', revision, 'deleted', deleted, 'payload', payload) order by revision), '[]'::jsonb),
            max(revision)
        from (
            select id, revision, deleted, payload from public.%I
            where revision > $1
            order by revision
            limit $2
        ) page
    $query$, v_table)
        into v_records, v_last
        using coalesce(after, 0), page_limit;

    if v_last is null then
        v_has_more := false;
    else
        execute format('select exists (select 1 from public.%I where revision > $1)', v_table)
            into v_has_more
            using v_last;
    end if;

    return jsonb_build_object('cursor_expired', false, 'records', v_records, 'has_more', v_has_more);
end;
$$;

grant execute on function public.sync_pull(text, bigint, integer, boolean) to authenticated;
revoke execute on function public.sync_pull(text, bigint, integer, boolean) from anon, public;

-- Removes tombstones older than the retention and records, per user and record
-- type, the highest removed revision. Runs as the owner, never as a user.
create or replace function public.sync_purge_tombstones(retention interval default interval '90 days')
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_type record;
begin
    for v_type in select record_type, table_name from public.sync_record_types loop
        execute format($purge$
            with removed as (
                delete from public.%I where deleted and updated_at < now() - $1 returning user_id, revision
            ), highest as (
                select user_id, max(revision) as through from removed group by user_id
            )
            insert into public.sync_tombstone_horizon (record_type, user_id, removed_through)
            select $2, user_id, through from highest
            on conflict (record_type, user_id) do update
                set removed_through = greatest(public.sync_tombstone_horizon.removed_through, excluded.removed_through)
        $purge$, v_type.table_name)
            using retention, v_type.record_type;
    end loop;
end;
$$;

revoke all on function public.sync_purge_tombstones(interval) from public, anon, authenticated;

do $$
begin
    if exists (select 1 from pg_extension where extname = 'pg_cron') then
        perform cron.schedule('sync-purge-tombstones', '17 3 * * *', 'select public.sync_purge_tombstones()');
    end if;
end;
$$;

