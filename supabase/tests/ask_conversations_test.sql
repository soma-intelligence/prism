-- Every chat in the database: conversations, their messages, idempotent
-- writes and the owner only rule.
begin;
select plan(17);

insert into auth.users (id, email) values
    ('00000000-0000-4000-8000-0000000000a1', 'a@example.test'),
    ('00000000-0000-4000-8000-0000000000b1', 'b@example.test');

set local role authenticated;
set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}';

select lives_ok($$insert into public.ask_conversations (id, title, created_at, updated_at)
    values ('22222222-2222-4222-8222-222222222222', 'How did I sleep?', '2026-10-01T08:00:00Z', '2026-10-01T08:00:00Z')$$,
    'A opens a conversation');
select lives_ok($$insert into public.ask_messages (conversation_id, client_id, role, content, created_at) values
    ('22222222-2222-4222-8222-222222222222', 't1:user', 'user', 'How did I sleep?', '2026-10-01T08:00:00Z'),
    ('22222222-2222-4222-8222-222222222222', 't1:assistant', 'assistant', 'You slept 7 h 10 min.', '2026-10-01T08:00:01Z')$$,
    'A stores a turn');
select lives_ok($$update public.ask_messages set model = 'chat-model-a' where client_id = 't1:assistant'$$,
    'A updates her own message');
select is((select last_message_preview from public.ask_conversations where id = '22222222-2222-4222-8222-222222222222'),
    'You slept 7 h 10 min.', 'the newest message is the preview');
select is((select updated_at from public.ask_conversations where id = '22222222-2222-4222-8222-222222222222'),
    '2026-10-01T08:00:01Z'::timestamptz, 'the conversation''s clock follows its newest message');

-- Idempotency: the same turn written twice is one row.
select lives_ok($$insert into public.ask_messages (conversation_id, client_id, role, content)
    values ('22222222-2222-4222-8222-222222222222', 't1:user', 'user', 'How did I sleep?')
    on conflict (user_id, client_id) do nothing$$,
    'a second write of the same turn is accepted');
select is((select count(*)::int from public.ask_messages where conversation_id = '22222222-2222-4222-8222-222222222222'), 2,
    'and changes nothing');
select throws_ok($$insert into public.ask_messages (conversation_id, client_id, role, content)
    values ('22222222-2222-4222-8222-222222222222', 't1:user', 'user', 'again')$$,
    '23505', 'a plain duplicate is refused');

-- A message whose conversation is not there yet opens it, titled from the question.
select lives_ok($$insert into public.ask_messages (conversation_id, client_id, role, content, created_at)
    values ('33333333-3333-4333-8333-333333333333', 't2:user', 'user', '  Can I   train hard tomorrow?  ', '2026-10-02T07:00:00Z')$$,
    'an offline turn uploads on its own');
select is((select title from public.ask_conversations where id = '33333333-3333-4333-8333-333333333333'),
    'Can I train hard tomorrow?', 'its conversation is opened and titled from the question');
select throws_ok($$insert into public.ask_conversations (kind, title) values ('mind', 'x')$$,
    '23514', 'only known kinds of chat');

set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-0000000000b1","role":"authenticated"}';
select is((select count(*)::int from public.ask_conversations), 0, 'B cannot read A''s conversations');
select is((select count(*)::int from public.ask_messages), 0, 'B cannot read A''s messages');
select throws_ok($$insert into public.ask_messages (conversation_id, client_id, role, content)
    values ('22222222-2222-4222-8222-222222222222', 'b1:user', 'user', 'Hello')$$,
    '23503', 'B cannot write into A''s conversation');
update public.ask_conversations set title = 'B was here' where id = '22222222-2222-4222-8222-222222222222';
delete from public.ask_conversations where id = '22222222-2222-4222-8222-222222222222';

set local request.jwt.claims to '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}';
select is((select title from public.ask_conversations where id = '22222222-2222-4222-8222-222222222222'),
    'How did I sleep?', 'B can neither rename nor delete it');
delete from public.ask_conversations where id = '22222222-2222-4222-8222-222222222222';
select is((select count(*)::int from public.ask_messages where conversation_id = '22222222-2222-4222-8222-222222222222'), 0,
    'deleting a conversation deletes its messages');

set local role anon;
select throws_ok($$select count(*) from public.ask_conversations$$, '42501', 'anon reads nothing');

select * from finish();
rollback;
