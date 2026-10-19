-- Ask Soma's history and rate limit, and the generated article columns.
begin;
select plan(9);

insert into auth.users (id, email) values
    ('00000000-0000-4000-8000-0000000000a1', 'a@example.test'),
    ('00000000-0000-4000-8000-0000000000b1', 'b@example.test');

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}';

select is(public.ask_take_quota(2), true, 'the first message of the hour is allowed');
select is(public.ask_take_quota(2), true, 'the second is allowed');
select is(public.ask_take_quota(2), false, 'the third over a limit of two is refused');
select is((select messages from public.ask_usage), 2, 'a refusal does not count');
select lives_ok($$insert into public.ask_messages (conversation_id, role, content) values ('11111111-1111-4111-8111-111111111111', 'user', 'How did I sleep?')$$,
    'A stores her question');
select throws_ok($$insert into public.ask_usage (user_id, window_start) values (auth.uid(), now())$$, '42501', 'nobody writes the usage table directly');

set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-0000000000b1","role":"authenticated"}';
select is((select count(*)::int from public.ask_messages), 0, 'B cannot read A''s conversation');
select is(public.ask_take_quota(2), true, 'B has her own allowance');

reset role;
select throws_ok($$insert into public.app_articles (slug, title, topic, generated_by) values ('x-gen', 'X', 'sleep', 'articles-generate')$$,
    '23514', 'a generated article must name its model');

select * from finish();
rollback;
