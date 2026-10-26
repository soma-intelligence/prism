-- Row level security and the shape of the app's data, checked as two users.
-- Runs under `supabase db test` (pgTAP) or, without Docker, with
-- supabase/scripts/local-test/run.sh on a plain Postgres 17.
begin;
select plan(53);

-- Two people. Their profiles come from the trigger on auth.users.
insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-4000-8000-00000000000a', 'a@example.test', '{"full_name": "Ada Lovelace"}'),
    ('00000000-0000-4000-8000-00000000000b', 'b@example.test', '{}');

select is((select first_name from public.profiles where id = '00000000-0000-4000-8000-00000000000a'), 'Ada', 'a new user gets a profile with the first name Apple shared');
select is((select count(*)::int from public.profiles where id = '00000000-0000-4000-8000-00000000000b'), 1, 'a user without a name still gets a profile');

-- As A ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000a","role":"authenticated"}';

select lives_ok($$update public.profiles set birth_date = '1990-05-01', sex = 'female', height_cm = 168, units = 'metric', avatar_path = '00000000-0000-4000-8000-00000000000a/avatar.jpg' where id = auth.uid()$$,
    'A updates her own profile');
select is((select count(*)::int from public.profiles), 1, 'A sees one profile, her own');
select throws_ok($$update public.profiles set avatar_path = 'someone-else/avatar.jpg' where id = auth.uid()$$, '23514',
    'an avatar path outside her own folder is refused');

-- Journal through the sync functions.
select is(
    public.sync_push('journal_days', '[{"id":"11111111-1111-4111-8111-111111111111","base_revision":null,"deleted":false,"payload":{"id":"11111111-1111-4111-8111-111111111111","day":"2026-10-03","tags_yes":["alcohol","sauna"],"tags_no":["nap"],"feeling":5}}]'::jsonb) -> 0 ->> 'outcome',
    'applied', 'A pushes a journal day');
select is((select day from public.journal_days where id = '11111111-1111-4111-8111-111111111111'), date '2026-10-03', 'the day column is projected from the payload');
select is((select tags_yes from public.journal_days where id = '11111111-1111-4111-8111-111111111111'), array['alcohol', 'sauna'], 'yes answers are projected in order');
select is((select tags_no from public.journal_days where id = '11111111-1111-4111-8111-111111111111'), array['nap'], 'no answers are projected');
select is((select feeling from public.journal_days where id = '11111111-1111-4111-8111-111111111111'), 5::smallint, 'the feeling is projected');
select is(
    public.sync_push('journal_days', '[{"id":"11111111-1111-4111-8111-111111111112","base_revision":null,"deleted":false,"payload":{"day":"not a day","feeling":"x","tags_yes":"nope"}}]'::jsonb) -> 0 ->> 'outcome',
    'applied', 'a payload with odd values is still stored');
select is((select day from public.journal_days where id = '11111111-1111-4111-8111-111111111112'), null::date, 'an unreadable day projects to null instead of failing the push');

select is(
    public.sync_push('scores_daily', '[{"id":"22222222-2222-4222-8222-222222222222","base_revision":null,"deleted":false,"payload":{"day":"2026-10-03","sleep":82,"recovery":64,"strain":null,"stress":31,"energy":140}}]'::jsonb) -> 0 ->> 'outcome',
    'applied', 'A pushes a day of scores');
select is((select sleep from public.scores_daily where id = '22222222-2222-4222-8222-222222222222'), 82::smallint, 'the sleep score is projected');
select is((select energy from public.scores_daily where id = '22222222-2222-4222-8222-222222222222'), null::smallint, 'a score outside 0 to 100 projects to null');

select is(
    public.sync_push('mood_logs', '[{"id":"33333333-3333-4333-8333-333333333333","base_revision":null,"deleted":false,"payload":{"logged_at":1791028800000,"kind":"momentary","valence":0.5,"labels":["calm"],"associations":["work"],"origin":"mind"}}]'::jsonb) -> 0 ->> 'outcome',
    'applied', 'A pushes a mood');
select is((select logged_at from public.mood_logs where id = '33333333-3333-4333-8333-333333333333'), timestamptz '2026-10-03 12:00:00+00', 'milliseconds since 1970 project to a timestamp');

select is(
    public.sync_push('track_logs', '[{"id":"44444444-4444-4444-8444-444444444444","base_revision":null,"deleted":false,"payload":{"kind":"drink","logged_at":1791028800000,"value":250,"unit":"ml","label":"coffee","detail":{"caffeine_mg":95}}}]'::jsonb) -> 0 ->> 'outcome',
    'applied', 'A pushes a drink');
select is((select (detail ->> 'caffeine_mg')::int from public.track_logs where id = '44444444-4444-4444-8444-444444444444'), 95, 'the detail object is kept');

select is(
    public.sync_push('check_in_answers', '[{"id":"55555555-5555-4555-8555-555555555555","base_revision":null,"deleted":false,"payload":{"day":"2026-10-03","question_id":"sleep-quality","answer_kind":"scale","answer_value":4,"skipped":false}}]'::jsonb) -> 0 ->> 'outcome',
    'applied', 'A pushes a check-in answer');

select is(
    public.sync_push('provider_connections', '[{"id":"66666666-6666-4666-8666-666666666666","base_revision":null,"deleted":false,"payload":{"provider":"oura","status":"connected","access_token":"secret"}}]'::jsonb) -> 0 ->> 'outcome',
    'rejected', 'a provider connection carrying a token is refused');
select is((select count(*)::int from public.provider_connections), 0, 'nothing of it is stored');

-- Health.
select lives_ok($$insert into public.health_samples (user_id, hk_uuid, metric, kind, value, unit, start_at, end_at, source_name, device_model)
    values (auth.uid(), 'aaaaaaaa-0000-4000-8000-000000000001', 'HKQuantityTypeIdentifierHeartRate', 'quantity', 61, 'countPerMinute', '2026-10-03 07:00+00', '2026-10-03 07:00+00', 'Watch', 'Watch Apple Inc.')$$,
    'A inserts a heart rate sample');
select lives_ok($$insert into public.health_samples (user_id, hk_uuid, metric, kind, value, unit, start_at, end_at)
    values (auth.uid(), 'aaaaaaaa-0000-4000-8000-000000000001', 'HKQuantityTypeIdentifierHeartRate', 'quantity', 62, 'countPerMinute', '2026-10-03 07:00+00', '2026-10-03 07:00+00')
    on conflict (user_id, hk_uuid) do update set value = excluded.value$$,
    'sending the same sample again is an upsert');
select is((select count(*)::int from public.health_samples), 1, 'the replayed sample is stored once');
select is((select value from public.health_samples), 62::double precision, 'and carries the newest value');
select throws_ok($$insert into public.health_samples (user_id, hk_uuid, metric, kind, value, unit, start_at, end_at)
    values ('00000000-0000-4000-8000-00000000000b', 'aaaaaaaa-0000-4000-8000-000000000002', 'm', 'quantity', 1, 'count', now(), now())$$,
    '42501', 'A cannot write a sample in B''s name');
select throws_ok($$insert into public.health_samples (user_id, hk_uuid, metric, kind, value, unit, start_at, end_at)
    values (auth.uid(), 'aaaaaaaa-0000-4000-8000-000000000003', 'm', 'quantity', 1, 'count', now(), now() - interval '1 hour')$$,
    '23514', 'a sample that ends before it starts is refused');
select lives_ok($$insert into public.health_daily (user_id, metric, day, time_zone, unit, sum) values (auth.uid(), 'HKQuantityTypeIdentifierStepCount', '2026-10-03', 'Europe/Paris', 'count', 8421)$$,
    'A writes a daily row');
select lives_ok($$insert into public.health_sync_state (user_id, installation_id, metric, anchor, samples_uploaded) values (auth.uid(), 'phone-a-0001', 'HKQuantityTypeIdentifierHeartRate', 'YW5jaG9y', 1)$$,
    'A records her upload state');
select lives_ok($$insert into public.devices (installation_id, platform, model) values ('phone-a-0001', 'ios', 'iPhone18,2')
    on conflict (user_id, installation_id) do update set model = excluded.model$$,
    'A registers her phone');

-- Storage.
select lives_ok($$insert into storage.objects (bucket_id, name) values ('avatars', '00000000-0000-4000-8000-00000000000a/avatar.jpg')$$,
    'A uploads her avatar into her own folder');
select throws_ok($$insert into storage.objects (bucket_id, name) values ('avatars', '00000000-0000-4000-8000-00000000000b/avatar.jpg')$$,
    '42501', 'A cannot put an avatar in B''s folder');
select throws_ok($$insert into storage.objects (bucket_id, name) values ('avatars', 'avatar.jpg')$$,
    '42501', 'A cannot put an avatar outside any folder');
select lives_ok($$insert into storage.objects (bucket_id, name) values ('health-uploads', '00000000-0000-4000-8000-00000000000a/exports/2026-10-03.zip')$$,
    'A uploads an export into her own folder');

-- As B ---------------------------------------------------------------------------
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000b","role":"authenticated"}';

select is((select count(*)::int from public.profiles where id = '00000000-0000-4000-8000-00000000000a'), 0, 'B cannot read A''s profile');
select is((select count(*)::int from public.journal_days), 0, 'B cannot read A''s journal');
select is(jsonb_array_length(public.sync_pull('journal_days', null, 100) -> 'records'), 0, 'B pulls none of A''s journal days');
select is((select count(*)::int from public.health_samples), 0, 'B cannot read A''s samples');
select is((select count(*)::int from public.health_daily), 0, 'B cannot read A''s daily rows');
select is((select count(*)::int from public.devices), 0, 'B cannot see A''s phone');
select is((select count(*)::int from storage.objects), 0, 'B cannot see A''s files');

update public.health_samples set value = 0;
update public.journal_days set payload = '{}'::jsonb;
delete from public.health_samples;

-- As A again, to see what B's writes did.
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000a","role":"authenticated"}';
select is((select value from public.health_samples), 62::double precision, 'B''s update did not reach A''s sample');
select is((select feeling from public.journal_days where id = '11111111-1111-4111-8111-111111111111'), 5::smallint, 'B''s update did not reach A''s journal');

-- anon -------------------------------------------------------------------------
reset role;
set local role anon;
set local request.jwt.claims to '{"role":"anon"}';
select throws_ok($$select count(*) from public.profiles$$, '42501', 'anon cannot read profiles at all');
select throws_ok($$select count(*) from public.health_samples$$, '42501', 'anon cannot read health samples at all');
select throws_ok($$select public.sync_pull('journal_days', null, 10)$$, '42501', 'anon cannot pull records');

-- Account deletion ---------------------------------------------------------------
reset role;
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000a","role":"authenticated"}';
-- Closing the account erases nothing: storage objects and rows stay.
select lives_ok($$update public.profiles set status = 'deleted' where id = auth.uid()$$, 'A may try to set her own status');
reset role;
select is((select status from public.profiles where id = '00000000-0000-4000-8000-00000000000a'), 'active',
    'only closing the account moves the status');
set local role authenticated;
select lives_ok($$select public.delete_my_account()$$, 'A closes her account');
reset role;
select is((select status from public.profiles where id = '00000000-0000-4000-8000-00000000000a'), 'deleted',
    'her profile is marked deleted');
select is((select banned_until from auth.users where id = '00000000-0000-4000-8000-00000000000a'), 'infinity'::timestamptz,
    'she can no longer sign in');
select ok((select count(*)::int from public.journal_days where user_id = '00000000-0000-4000-8000-00000000000a')
    + (select count(*)::int from public.profiles where id = '00000000-0000-4000-8000-00000000000a') >= 2,
    'nothing of hers is erased');

select * from finish();
rollback;
