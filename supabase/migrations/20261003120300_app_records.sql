-- What a person logs in the app, as synced records.
--
-- Each table is a record table of the sync foundation
-- (public.sync_create_record_table): id, user_id, revision, deleted, payload,
-- updated_at, owner only row level security, and push and pull through
-- sync_push and sync_pull. The app's outbox (SyncCore) pushes every change,
-- retries with backoff, and a new phone pulls everything back.
--
-- On top of that layout every table gets typed columns, filled from the
-- payload by a trigger on each write, so the data can be queried as columns
-- (journal_days.day, scores_daily.sleep) without parsing JSON. The trigger
-- never raises: a value it cannot read becomes null, so one odd record can
-- never block a push of the others.
--
-- Payloads carry snake case keys equal to the column names. Times are
-- milliseconds since 1970 (SyncCore's canonical JSON); days are yyyy-MM-dd in
-- the person's calendar.

-- Payload readers ---------------------------------------------------------------

create or replace function public.payload_date(p jsonb, k text)
returns date
language plpgsql
immutable
set search_path = ''
as $$
begin
    return (p ->> k)::date;
exception when others then
    return null;
end;
$$;

create or replace function public.payload_time(p jsonb, k text)
returns timestamptz
language plpgsql
immutable
set search_path = ''
as $$
begin
    return to_timestamp((p ->> k)::double precision / 1000.0);
exception when others then
    return null;
end;
$$;

create or replace function public.payload_float(p jsonb, k text)
returns double precision
language plpgsql
immutable
set search_path = ''
as $$
begin
    return (p ->> k)::double precision;
exception when others then
    return null;
end;
$$;

create or replace function public.payload_int(p jsonb, k text)
returns integer
language plpgsql
immutable
set search_path = ''
as $$
begin
    return round((p ->> k)::numeric)::integer;
exception when others then
    return null;
end;
$$;

create or replace function public.payload_bool(p jsonb, k text)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
begin
    return (p ->> k)::boolean;
exception when others then
    return null;
end;
$$;

create or replace function public.payload_text(p jsonb, k text, max_length integer default 2000)
returns text
language plpgsql
immutable
set search_path = ''
as $$
begin
    if jsonb_typeof(p -> k) is distinct from 'string' then
        return null;
    end if;
    return left(p ->> k, max_length);
end;
$$;

create or replace function public.payload_texts(p jsonb, k text)
returns text[]
language plpgsql
immutable
set search_path = ''
as $$
begin
    if jsonb_typeof(p -> k) is distinct from 'array' then
        return '{}'::text[];
    end if;
    return coalesce((select array_agg(left(value, 200) order by ordinality) from jsonb_array_elements_text(p -> k) with ordinality), '{}'::text[]);
exception when others then
    return '{}'::text[];
end;
$$;

-- The sync foundation's tables answer to authenticated only; the service role
-- gets every privilege on each, and anon nothing.
create or replace function public.app_record_table(p_record_type text, p_table text, p_comment text)
returns void
language plpgsql
as $$
begin
    perform public.sync_create_record_table(p_record_type, p_table);
    execute format('revoke all on public.%I from anon', p_table);
    execute format('grant all on public.%I to service_role', p_table);
    execute format('comment on table public.%I is %L', p_table, p_comment);
end;
$$;

revoke all on function public.app_record_table(text, text, text) from public, anon, authenticated;

-- journal_days ------------------------------------------------------------------

select public.app_record_table('journal_days', 'journal_days',
    'The Journal, one record per day (id derived from the user and the day). Each tag is yes, no, or unanswered: tags_yes and tags_no hold the answered ones, a tag in neither was not asked. feeling is 0 (very unpleasant) to 6 (very pleasant).');

alter table public.journal_days
    add column day date,
    add column tags_yes text[] not null default '{}',
    add column tags_no text[] not null default '{}',
    add column feeling smallint;

create unique index journal_days_user_day_idx on public.journal_days (user_id, day) where not deleted;

create or replace function public.journal_days_project()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.day := public.payload_date(new.payload, 'day');
    new.tags_yes := public.payload_texts(new.payload, 'tags_yes');
    new.tags_no := public.payload_texts(new.payload, 'tags_no');
    new.feeling := case when public.payload_int(new.payload, 'feeling') between 0 and 6 then public.payload_int(new.payload, 'feeling') end;
    return new;
end;
$$;

create trigger sync_project before insert or update on public.journal_days
for each row execute function public.journal_days_project();

-- check_in_answers --------------------------------------------------------------

select public.app_record_table('check_in_answers', 'check_in_answers',
    'One answer to one "Soma asks" question on one day (id derived from the user, the day and the question). answer_kind is yes, no, scale (1 to 5) or number; skipped marks a question passed over.');

alter table public.check_in_answers
    add column day date,
    add column question_id text,
    add column answer_kind text,
    add column answer_value integer,
    add column skipped boolean not null default false,
    add column question_text text;

create unique index check_in_answers_user_day_question_idx on public.check_in_answers (user_id, day, question_id) where not deleted;

create or replace function public.check_in_answers_project()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.day := public.payload_date(new.payload, 'day');
    new.question_id := public.payload_text(new.payload, 'question_id', 120);
    new.answer_kind := case when public.payload_text(new.payload, 'answer_kind', 20) in ('yes', 'no', 'scale', 'number')
        then public.payload_text(new.payload, 'answer_kind', 20) end;
    new.answer_value := public.payload_int(new.payload, 'answer_value');
    new.skipped := coalesce(public.payload_bool(new.payload, 'skipped'), false);
    new.question_text := public.payload_text(new.payload, 'question_text', 500);
    return new;
end;
$$;

create trigger sync_project before insert or update on public.check_in_answers
for each row execute function public.check_in_answers_project();

-- mood_logs ---------------------------------------------------------------------

select public.app_record_table('mood_logs', 'mood_logs',
    'State of mind: a momentary emotion or a daily mood, valence -1 (very unpleasant) to 1 (very pleasant) on Apple''s scale, with feeling labels and associations. origin says which surface logged it (mind or track).');

alter table public.mood_logs
    add column logged_at timestamptz,
    add column kind text,
    add column valence double precision,
    add column labels text[] not null default '{}',
    add column associations text[] not null default '{}',
    add column origin text;

create index mood_logs_user_logged_idx on public.mood_logs (user_id, logged_at desc);

create or replace function public.mood_logs_project()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.logged_at := public.payload_time(new.payload, 'logged_at');
    new.kind := case when public.payload_text(new.payload, 'kind', 20) in ('momentary', 'daily') then public.payload_text(new.payload, 'kind', 20) end;
    new.valence := greatest(-1, least(1, public.payload_float(new.payload, 'valence')));
    new.labels := public.payload_texts(new.payload, 'labels');
    new.associations := public.payload_texts(new.payload, 'associations');
    new.origin := public.payload_text(new.payload, 'origin', 20);
    return new;
end;
$$;

create trigger sync_project before insert or update on public.mood_logs
for each row execute function public.mood_logs_project();

-- mind_check_ins ----------------------------------------------------------------

select public.app_record_table('mind_check_ins', 'mind_check_ins',
    'A quick Mind check-in: energy, mood and focus on five steps (0 to 4, null when skipped), and the answer to the question the body asked, when it asked one.');

alter table public.mind_check_ins
    add column logged_at timestamptz,
    add column energy smallint,
    add column mood smallint,
    add column focus smallint,
    add column question text,
    add column answer text;

create index mind_check_ins_user_logged_idx on public.mind_check_ins (user_id, logged_at desc);

create or replace function public.mind_check_ins_project()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.logged_at := public.payload_time(new.payload, 'logged_at');
    new.energy := case when public.payload_int(new.payload, 'energy') between 0 and 4 then public.payload_int(new.payload, 'energy') end;
    new.mood := case when public.payload_int(new.payload, 'mood') between 0 and 4 then public.payload_int(new.payload, 'mood') end;
    new.focus := case when public.payload_int(new.payload, 'focus') between 0 and 4 then public.payload_int(new.payload, 'focus') end;
    new.question := public.payload_text(new.payload, 'question', 500);
    new.answer := case when public.payload_text(new.payload, 'answer', 20) in ('yes', 'no', 'notSure') then public.payload_text(new.payload, 'answer', 20) end;
    return new;
end;
$$;

create trigger sync_project before insert or update on public.mind_check_ins
for each row execute function public.mind_check_ins_project();

-- track_logs --------------------------------------------------------------------

select public.app_record_table('track_logs', 'track_logs',
    'Everything Track logs that is not a Journal answer: drinks (ml, caffeine), meals (macros, portions), supplement doses, timed practices, fasts, body measures (weight, height, waist) and the morning rating. kind names it, value and unit carry its one number, detail the rest.');

alter table public.track_logs
    add column kind text,
    add column logged_at timestamptz,
    add column ended_at timestamptz,
    add column value double precision,
    add column unit text,
    add column label text,
    add column detail jsonb not null default '{}'::jsonb;

create index track_logs_user_kind_logged_idx on public.track_logs (user_id, kind, logged_at desc);

create or replace function public.track_logs_project()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.kind := public.payload_text(new.payload, 'kind', 40);
    new.logged_at := public.payload_time(new.payload, 'logged_at');
    new.ended_at := public.payload_time(new.payload, 'ended_at');
    new.value := public.payload_float(new.payload, 'value');
    new.unit := public.payload_text(new.payload, 'unit', 40);
    new.label := public.payload_text(new.payload, 'label', 200);
    new.detail := case when jsonb_typeof(new.payload -> 'detail') = 'object' then new.payload -> 'detail' else '{}'::jsonb end;
    return new;
end;
$$;

create trigger sync_project before insert or update on public.track_logs
for each row execute function public.track_logs_project();

-- lab_results -------------------------------------------------------------------

select public.app_record_table('lab_results', 'lab_results',
    'One blood panel: when it was drawn, the lab, and its markers as [{"marker", "value", "unit"}]. Read from a photographed or typed report on the phone.');

alter table public.lab_results
    add column collected_on date,
    add column lab_name text,
    add column markers jsonb not null default '[]'::jsonb;

create index lab_results_user_collected_idx on public.lab_results (user_id, collected_on desc);

create or replace function public.lab_results_project()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.collected_on := public.payload_date(new.payload, 'collected_on');
    new.lab_name := public.payload_text(new.payload, 'lab_name', 200);
    new.markers := case when jsonb_typeof(new.payload -> 'markers') = 'array' then new.payload -> 'markers' else '[]'::jsonb end;
    return new;
end;
$$;

create trigger sync_project before insert or update on public.lab_results
for each row execute function public.lab_results_project();

-- scores_daily ------------------------------------------------------------------

select public.app_record_table('scores_daily', 'scores_daily',
    'Soma''s 0 to 100 scores for one day as the app showed them (id derived from the user and the day): sleep, recovery, strain, stress, energy. Null where the data gate was not met.');

alter table public.scores_daily
    add column day date,
    add column sleep smallint,
    add column recovery smallint,
    add column strain smallint,
    add column stress smallint,
    add column energy smallint;

create unique index scores_daily_user_day_idx on public.scores_daily (user_id, day) where not deleted;

create or replace function public.scores_daily_project()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.day := public.payload_date(new.payload, 'day');
    new.sleep := case when public.payload_int(new.payload, 'sleep') between 0 and 100 then public.payload_int(new.payload, 'sleep') end;
    new.recovery := case when public.payload_int(new.payload, 'recovery') between 0 and 100 then public.payload_int(new.payload, 'recovery') end;
    new.strain := case when public.payload_int(new.payload, 'strain') between 0 and 100 then public.payload_int(new.payload, 'strain') end;
    new.stress := case when public.payload_int(new.payload, 'stress') between 0 and 100 then public.payload_int(new.payload, 'stress') end;
    new.energy := case when public.payload_int(new.payload, 'energy') between 0 and 100 then public.payload_int(new.payload, 'energy') end;
    return new;
end;
$$;

create trigger sync_project before insert or update on public.scores_daily
for each row execute function public.scores_daily_project();

-- notification_inbox ------------------------------------------------------------

select public.app_record_table('notification_inbox', 'notification_inbox',
    'The in-app notification inbox: what Soma delivered, when, and whether it was read.');

alter table public.notification_inbox
    add column delivered_at timestamptz,
    add column kind text,
    add column title text,
    add column body text,
    add column is_read boolean not null default false,
    add column deep_link text;

create index notification_inbox_user_delivered_idx on public.notification_inbox (user_id, delivered_at desc);

create or replace function public.notification_inbox_project()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.delivered_at := public.payload_time(new.payload, 'delivered_at');
    new.kind := public.payload_text(new.payload, 'kind', 60);
    new.title := public.payload_text(new.payload, 'title', 300);
    new.body := public.payload_text(new.payload, 'body', 2000);
    new.is_read := coalesce(public.payload_bool(new.payload, 'is_read'), false);
    new.deep_link := public.payload_text(new.payload, 'deep_link', 500);
    return new;
end;
$$;

create trigger sync_project before insert or update on public.notification_inbox
for each row execute function public.notification_inbox_project();

-- provider_connections ----------------------------------------------------------

select public.app_record_table('provider_connections', 'provider_connections',
    'Which outside services (Oura, Whoop, Withings...) the person linked, their state, the account label they show, and the last sync. Never a token: OAuth tokens stay in the phone''s Keychain, and a payload naming one is refused.');

alter table public.provider_connections
    add column provider text,
    add column status text,
    add column account_label text,
    add column connected_at timestamptz,
    add column last_sync_at timestamptz,
    add constraint provider_connections_no_secrets check (
        not (payload ?| array['access_token', 'refresh_token', 'id_token', 'token', 'client_secret', 'code', 'password'])
    );

create unique index provider_connections_user_provider_idx on public.provider_connections (user_id, provider) where not deleted;

create or replace function public.provider_connections_project()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.provider := public.payload_text(new.payload, 'provider', 60);
    new.status := public.payload_text(new.payload, 'status', 40);
    new.account_label := public.payload_text(new.payload, 'account_label', 200);
    new.connected_at := public.payload_time(new.payload, 'connected_at');
    new.last_sync_at := public.payload_time(new.payload, 'last_sync_at');
    return new;
end;
$$;

create trigger sync_project before insert or update on public.provider_connections
for each row execute function public.provider_connections_project();

-- The projection functions run as triggers only.
revoke execute on function public.journal_days_project(), public.check_in_answers_project(), public.mood_logs_project(),
    public.mind_check_ins_project(), public.track_logs_project(), public.lab_results_project(), public.scores_daily_project(),
    public.notification_inbox_project(), public.provider_connections_project()
    from public, anon, authenticated;

-- The payload readers run inside the triggers, as the writing role.
grant execute on function public.payload_date(jsonb, text), public.payload_time(jsonb, text), public.payload_float(jsonb, text),
    public.payload_int(jsonb, text), public.payload_bool(jsonb, text), public.payload_text(jsonb, text, integer),
    public.payload_texts(jsonb, text)
    to authenticated, service_role;
