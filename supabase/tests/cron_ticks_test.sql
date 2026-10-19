-- The two cron ticks (news_ingest_tick, articles_generate_tick) read the project
-- address and the service role key from Vault. Without both they do nothing, and
-- with both they post to the address in Vault and to no other: the key must never
-- leave for a project its owner did not name.
begin;
select plan(11);
set local client_min_messages = error;

select lives_ok($$select public.news_ingest_tick(), public.articles_generate_tick()$$,
    'with an empty Vault both ticks return quietly');
select is((select count(*)::int from net.calls), 0, 'with an empty Vault nothing is sent');

insert into vault.secrets (name, decrypted_secret) values ('service_role_key', 'test-key');
do $$ begin perform public.news_ingest_tick(); perform public.articles_generate_tick(); end $$;
select is((select count(*)::int from net.calls), 0, 'a key without a project_url sends nothing, so the key goes nowhere');

insert into vault.secrets (name, decrypted_secret) values ('project_url', 'https://abc123.supabase.co/');
do $$ begin perform public.news_ingest_tick(); perform public.articles_generate_tick(); end $$;
select is((select count(*)::int from net.calls), 2, 'with both secrets each tick sends one request');
select is((select url from net.calls where url like '%news-ingest'),
    'https://abc123.supabase.co/functions/v1/news-ingest', 'the news request goes to the project in Vault, trailing slash trimmed');
select is((select url from net.calls where url like '%articles-generate'),
    'https://abc123.supabase.co/functions/v1/articles-generate', 'the article request goes to the project in Vault');
select is((select count(*)::int from net.calls where url not like 'https://abc123.supabase.co/%'), 0,
    'no request goes anywhere else');
select is((select count(*)::int from net.calls where headers ->> 'Authorization' = 'Bearer test-key'), 2,
    'both carry the key from Vault');
select is((select count(*)::int from net.calls where body = '{"trigger": "cron"}'::jsonb and timeout = 10000), 2,
    'the body and the timeout are as before');

delete from vault.secrets where name = 'service_role_key';
delete from net.calls;
do $$ begin perform public.news_ingest_tick(); end $$;
select is((select count(*)::int from net.calls), 0, 'a project_url without a key sends nothing');
select is((select count(*)::int from cron.job where jobname in ('news-ingest', 'articles-generate')), 2,
    'both ticks are scheduled');

select * from finish();
rollback;
