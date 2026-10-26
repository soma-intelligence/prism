-- Account deletion closes the account, it erases nothing (owner rule,
-- 2026-10-03, restated 2026-10-24: "Pas de suppression de compte côté
-- serveur"). The profile is marked deleted, the auth user is banned so
-- sign in is refused and sync stops, and every row and stored file stays.
-- An admin reverses it by setting the status back to active and clearing
-- auth.users.banned_until.

alter table public.profiles
    add column status text not null default 'active'
        constraint profiles_status_known check (status in ('active', 'deleted')),
    add column deleted_at timestamptz;

comment on column public.profiles.status is
    'active, or deleted when the person closed the account; nothing is erased and an admin can set it back.';

-- Only the account closing function and the service role move the status:
-- a person's own update of their profile never touches it.
create or replace function public.profiles_keep_status()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if current_user in ('anon', 'authenticated')
        and (new.status is distinct from old.status or new.deleted_at is distinct from old.deleted_at) then
        new.status := old.status;
        new.deleted_at := old.deleted_at;
    end if;
    return new;
end;
$$;

create trigger profiles_keep_status
    before update on public.profiles
    for each row execute function public.profiles_keep_status();

-- The App Store asks that an account made in the app can be deleted in the
-- app: here that means closed. The function runs as its owner, so its own
-- update passes the trigger above.
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
    update public.profiles
        set status = 'deleted', deleted_at = coalesce(deleted_at, now()), updated_at = now()
        where id = v_user;
    update auth.users set banned_until = 'infinity' where id = v_user;
end;
$$;

revoke execute on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
