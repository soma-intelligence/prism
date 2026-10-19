-- The handful of pgTAP functions the tests use, for a Postgres without the
-- extension. Under `supabase db test` the real pgTAP is used instead.
create schema if not exists tap;
create table tap.state (n integer not null, failed integer not null);
insert into tap.state values (0, 0);
grant usage on schema tap to public;
grant select, update on tap.state to public;

create function public.plan(integer) returns text language sql as $$ select '1..' || $1 $$;

create function public.ok(passed boolean, description text) returns text
language plpgsql security definer as $$
declare v integer;
begin
    update tap.state set n = n + 1, failed = failed + case when coalesce(passed, false) then 0 else 1 end returning n into v;
    return case when coalesce(passed, false) then 'ok ' else 'not ok ' end || v || ' - ' || description;
end;
$$;

create function public.is(have anyelement, want anyelement, description text) returns text
language plpgsql as $$
begin
    if have is not distinct from want then
        return public.ok(true, description);
    end if;
    return public.ok(false, description || ' (have ' || coalesce(have::text, 'null') || ', want ' || coalesce(want::text, 'null') || ')');
end;
$$;

create function public.throws_ok(query text, errcode text, description text) returns text
language plpgsql as $$
begin
    execute query;
    return public.ok(false, description || ' (no error)');
exception when others then
    if sqlstate = errcode then
        return public.ok(true, description);
    end if;
    return public.ok(false, description || ' (got ' || sqlstate || ': ' || sqlerrm || ')');
end;
$$;

create function public.lives_ok(query text, description text) returns text
language plpgsql as $$
begin
    execute query;
    return public.ok(true, description);
exception when others then
    return public.ok(false, description || ' (' || sqlstate || ': ' || sqlerrm || ')');
end;
$$;

create function public.finish() returns setof text language plpgsql security definer as $$
declare f integer;
begin
    select failed into f from tap.state;
    update tap.state set n = 0, failed = 0;
    if f > 0 then
        return next '# Looks like you failed ' || f || ' test(s)';
    end if;
end;
$$;

grant execute on all functions in schema public to public;
