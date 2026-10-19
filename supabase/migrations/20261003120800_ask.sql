-- Ask Soma: the conversation history and the per person rate limit.
--
-- The Edge Function ask-soma runs with the caller's own JWT: it takes a unit
-- of quota through ask_take_quota(), streams the model's answer, and stores
-- both turns in ask_messages, all under row level security, so the function
-- never needs the service role. History syncs to every phone the person signs
-- in on.

create table public.ask_messages (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    conversation_id uuid not null,
    role text not null
        constraint ask_messages_role_known check (role in ('user', 'assistant')),
    content text not null
        constraint ask_messages_content_length check (char_length(content) between 1 and 20000),
    -- The deployment that answered, on assistant turns.
    model text,
    prompt_tokens integer,
    completion_tokens integer,
    created_at timestamptz not null default now()
);

comment on table public.ask_messages is
    'Ask Soma conversations, one row per turn. Written by the ask-soma function with the person''s own token; the numbers the app sent as context are not stored.';

create index ask_messages_user_conversation_idx on public.ask_messages (user_id, conversation_id, created_at);
create index ask_messages_user_created_idx on public.ask_messages (user_id, created_at desc);

alter table public.ask_messages enable row level security;

create policy ask_messages_select_own on public.ask_messages
for select to authenticated using (user_id = (select auth.uid()));
create policy ask_messages_insert_own on public.ask_messages
for insert to authenticated with check (user_id = (select auth.uid()));
create policy ask_messages_delete_own on public.ask_messages
for delete to authenticated using (user_id = (select auth.uid()));

revoke all on public.ask_messages from anon, authenticated;
grant select, insert, delete on public.ask_messages to authenticated;
grant all on public.ask_messages to service_role;

-- One row per person per hour.
create table public.ask_usage (
    user_id uuid not null references auth.users (id) on delete cascade,
    window_start timestamptz not null,
    messages integer not null default 0,
    primary key (user_id, window_start)
);

comment on table public.ask_usage is 'Ask Soma messages per person per clock hour, for the rate limit. Written only through ask_take_quota().';

alter table public.ask_usage enable row level security;
create policy ask_usage_select_own on public.ask_usage
for select to authenticated using (user_id = (select auth.uid()));
revoke all on public.ask_usage from anon, authenticated;
grant select on public.ask_usage to authenticated;
grant all on public.ask_usage to service_role;

-- Takes one message from the caller's hourly allowance. True when it was
-- there to take; false once `per_hour` messages were sent this hour.
create or replace function public.ask_take_quota(per_hour integer default 60)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user uuid := auth.uid();
    v_window timestamptz := date_trunc('hour', now());
    v_count integer;
begin
    if v_user is null then
        raise exception 'ask_take_quota requires an authenticated user' using errcode = '28000';
    end if;
    insert into public.ask_usage (user_id, window_start, messages)
    values (v_user, v_window, 1)
    on conflict (user_id, window_start) do update set messages = public.ask_usage.messages + 1
    returning messages into v_count;
    if v_count > greatest(per_hour, 1) then
        update public.ask_usage set messages = messages - 1 where user_id = v_user and window_start = v_window;
        return false;
    end if;
    return true;
end;
$$;

revoke execute on function public.ask_take_quota(integer) from public, anon;
grant execute on function public.ask_take_quota(integer) to authenticated;

-- Old windows are no use to the limit.
select cron.schedule('ask-usage-retention', '41 4 * * *', $$delete from public.ask_usage where window_start < now() - interval '7 days'$$);
