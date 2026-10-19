-- Every chat lives here: one row per conversation in ask_conversations, its
-- turns in ask_messages, both readable and writable by their owner only.
--
-- Two writers, one row per turn: the ask-soma function stores what the model
-- answered, and the app uploads every turn it kept (answers given offline
-- from the phone's own numbers, turns asked before signing in). Both name a
-- message by the same client id (`<turn id>:user`, `<turn id>:assistant`),
-- unique per person, so whichever writes second changes nothing.
--
-- A message whose conversation is not here yet opens it (title from the
-- question), and every message moves its conversation's clock, preview and
-- model, so the row stays right whoever wrote the turn. Deleting a
-- conversation deletes its messages.

create table public.ask_conversations (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    -- What kind of chat. Only Ask Soma is a conversation today; another kind
    -- joins this list when one exists.
    kind text not null default 'ask'
        constraint ask_conversations_kind_known check (kind in ('ask')),
    title text not null default ''
        constraint ask_conversations_title_length check (char_length(title) <= 200),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    archived boolean not null default false,
    last_message_preview text
        constraint ask_conversations_preview_length check (char_length(last_message_preview) <= 280),
    -- The deployment that answered last.
    model text,
    -- Lets a message name its conversation and its owner in one key, so a
    -- message can never hang on someone else's conversation.
    constraint ask_conversations_id_user_key unique (id, user_id)
);

comment on table public.ask_conversations is
    'Chats with Soma, one row per conversation. Written by the app and by ask-soma with the person''s own token; the clock, preview and model follow its messages.';

create index ask_conversations_user_updated_idx on public.ask_conversations (user_id, updated_at desc);

alter table public.ask_conversations enable row level security;

create policy ask_conversations_select_own on public.ask_conversations
for select to authenticated using (user_id = (select auth.uid()));
create policy ask_conversations_insert_own on public.ask_conversations
for insert to authenticated with check (user_id = (select auth.uid()));
create policy ask_conversations_update_own on public.ask_conversations
for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy ask_conversations_delete_own on public.ask_conversations
for delete to authenticated using (user_id = (select auth.uid()));

revoke all on public.ask_conversations from anon, authenticated;
grant select, insert, update, delete on public.ask_conversations to authenticated;
grant all on public.ask_conversations to service_role;

-- A conversation's title from its first question: one line, at most 80
-- characters.
create or replace function public.ask_title(question text)
returns text
language sql
immutable
set search_path = ''
as $$
    select left(btrim(regexp_replace(coalesce(question, ''), '\s+', ' ', 'g')), 80)
$$;

-- The messages: the client id that makes a second write of a turn harmless,
-- an error flag for an answer that stopped halfway, and what the app shows
-- beside an answer (its sources and its move) so a new phone draws it whole.
alter table public.ask_messages
    add column client_id text not null default gen_random_uuid()::text
        constraint ask_messages_client_id_length check (char_length(client_id) between 1 and 100),
    add column is_error boolean not null default false,
    add column meta jsonb not null default '{}'::jsonb
        constraint ask_messages_meta_object check (jsonb_typeof(meta) = 'object' and pg_column_size(meta) <= 8000);

alter table public.ask_messages
    add constraint ask_messages_user_client_key unique (user_id, client_id);

-- Messages stored before this migration get their conversation.
insert into public.ask_conversations (id, user_id, title, created_at, updated_at)
select distinct on (m.conversation_id)
    m.conversation_id, m.user_id, public.ask_title(m.content), m.created_at, m.created_at
from public.ask_messages m
order by m.conversation_id, m.created_at
on conflict (id) do nothing;

alter table public.ask_messages
    add constraint ask_messages_conversation_fkey foreign key (conversation_id, user_id)
        references public.ask_conversations (id, user_id) on delete cascade;

comment on table public.ask_messages is
    'Chat turns, one row per message, under ask_conversations. Written by ask-soma and by the app with the person''s own token; (user_id, client_id) makes a second write of the same turn harmless. The numbers the app sent as context are not stored.';

-- The function replaces an answer it wrote again for the same turn (a retry),
-- so a person may update their own messages.
create policy ask_messages_update_own on public.ask_messages
for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
grant update on public.ask_messages to authenticated;

-- Opens the conversation a message names when it is not there yet. Runs as
-- the writer, under row level security: a conversation id someone else owns
-- is left alone here and the foreign key then refuses the message.
create or replace function public.ask_messages_open_conversation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    insert into public.ask_conversations (id, user_id, title, created_at, updated_at)
    values (
        new.conversation_id,
        new.user_id,
        case when new.role = 'user' then public.ask_title(new.content) else '' end,
        new.created_at,
        new.created_at
    )
    on conflict (id) do nothing;
    return new;
end;
$$;

create trigger ask_messages_open_conversation
before insert on public.ask_messages
for each row execute function public.ask_messages_open_conversation();

-- Moves the conversation's clock, preview and model to its newest message,
-- and titles a conversation that has no title yet from its first question.
create or replace function public.ask_messages_touch_conversation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    update public.ask_conversations c set
        updated_at = greatest(c.updated_at, new.created_at),
        last_message_preview = case when new.created_at >= c.updated_at then left(new.content, 280) else c.last_message_preview end,
        model = case when new.model is not null and new.created_at >= c.updated_at then new.model else c.model end,
        title = case when c.title = '' and new.role = 'user' then public.ask_title(new.content) else c.title end
    where c.id = new.conversation_id and c.user_id = new.user_id;
    return null;
end;
$$;

create trigger ask_messages_touch_conversation
after insert or update of content on public.ask_messages
for each row execute function public.ask_messages_touch_conversation();

create index ask_messages_conversation_created_idx on public.ask_messages (conversation_id, created_at);
