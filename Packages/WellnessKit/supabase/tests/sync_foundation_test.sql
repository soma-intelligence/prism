-- Run with: supabase db test (needs the local Supabase stack, which needs Docker).
begin;
select plan(14);

insert into auth.users (id, email)
values
    ('00000000-0000-4000-8000-00000000000a', 'user-a@example.test'),
    ('00000000-0000-4000-8000-00000000000b', 'user-b@example.test');

-- Everything below runs as user A unless stated otherwise.
set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000a","role":"authenticated"}';

select is(
    public.sync_push('sync_probe', '[{"id":"11111111-1111-4111-8111-111111111111","base_revision":null,"deleted":false,"payload":{"body":"one"}}]'::jsonb) -> 0 ->> 'outcome',
    'applied',
    'an insert without base revision is applied'
);

select is(
    public.sync_push('sync_probe', jsonb_build_array(jsonb_build_object(
        'id', '11111111-1111-4111-8111-111111111111',
        'base_revision', (select revision - 1 from public.soma_sync_probe where id = '11111111-1111-4111-8111-111111111111'),
        'deleted', false,
        'payload', '{"body":"stale"}'::jsonb))) -> 0 ->> 'outcome',
    'conflict',
    'a stale base revision is a conflict'
);

select ok(
    (public.sync_push('sync_probe', jsonb_build_array(jsonb_build_object(
        'id', '11111111-1111-4111-8111-111111111111',
        'base_revision', (select revision from public.soma_sync_probe where id = '11111111-1111-4111-8111-111111111111'),
        'deleted', false,
        'payload', '{"body":"two"}'::jsonb))) -> 0 ->> 'revision')::bigint
    > 0,
    'a matching base revision is applied with a revision'
);

select is(
    public.sync_push('sync_probe', '[{"id":"11111111-1111-4111-8111-111111111111","base_revision":null,"deleted":false,"payload":{"body":"two"}}]'::jsonb) -> 0 ->> 'revision',
    (select revision::text from public.soma_sync_probe where id = '11111111-1111-4111-8111-111111111111'),
    'replaying the current content is applied without a new revision'
);

select is(
    public.sync_push('sync_probe', '[{"id":"99999999-9999-4999-8999-999999999999","base_revision":5,"deleted":false,"payload":{"body":"x"}}]'::jsonb) -> 0 -> 'record' ->> 'deleted',
    'true',
    'a base revision for a missing record is a conflict with a tombstone'
);

select is(
    (public.sync_pull('sync_probe', null, 10) -> 'records') -> 0 ->> 'id',
    '11111111-1111-4111-8111-111111111111',
    'pull returns the user''s records'
);

select is(
    (public.sync_pull('sync_probe', 0, 1) ->> 'has_more')::boolean,
    false,
    'has_more is false when the page holds the last record'
);

-- User B sees nothing of user A and cannot take over A's id.
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000b","role":"authenticated"}';

select is(
    jsonb_array_length(public.sync_pull('sync_probe', null, 10) -> 'records'),
    0,
    'row level security hides other users'' records from pull'
);

select is(
    (select count(*) from public.soma_sync_probe),
    0::bigint,
    'row level security hides other users'' rows from select'
);

select is(
    public.sync_push('sync_probe', '[{"id":"11111111-1111-4111-8111-111111111111","base_revision":null,"deleted":false,"payload":{"body":"hijack"}}]'::jsonb) -> 0 ->> 'outcome',
    'rejected',
    'an id owned by another user is rejected'
);

-- Back to user A: delete, purge as the service, then an old cursor expires.
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-00000000000a","role":"authenticated"}';
select public.sync_push('sync_probe', jsonb_build_array(jsonb_build_object(
    'id', '11111111-1111-4111-8111-111111111111',
    'base_revision', (select revision from public.soma_sync_probe where id = '11111111-1111-4111-8111-111111111111'),
    'deleted', true,
    'payload', '{"body":"two"}'::jsonb)));

reset role;
select public.sync_purge_tombstones(interval '-1 second');
set local role authenticated;

select is(
    (public.sync_pull('sync_probe', 1, 10) ->> 'cursor_expired')::boolean,
    true,
    'a cursor older than purged tombstones is expired'
);

select is(
    (public.sync_pull('sync_probe', 1, 10, true) ->> 'cursor_expired')::boolean,
    false,
    'a resync page never reports an expired cursor'
);

select throws_ok(
    $$ select public.sync_push('no_such_type', '[]'::jsonb) $$,
    '22023',
    null,
    'an unknown record type is refused'
);

reset role;
set local role anon;
set local request.jwt.claims to '{"role":"anon"}';
select throws_ok(
    $$ select public.sync_push('sync_probe', '[]'::jsonb) $$,
    null,
    null,
    'anonymous callers cannot push'
);

select * from finish();
rollback;
