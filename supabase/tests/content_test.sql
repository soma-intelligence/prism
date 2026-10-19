-- The two public content tables the app reads with the publishable key:
-- app_articles (the Explore library) and news_items (the Latest rail).
begin;
select plan(9);

insert into public.app_articles (slug, title, topic, body, published, published_at) values
    ('sleep-pressure', 'Sleep pressure', 'sleep', 'Body.', true, now() - interval '1 day'),
    ('draft-piece', 'Draft', 'mind', 'Body.', false, null),
    ('scheduled', 'Later', 'heart', 'Body.', true, now() + interval '1 day');

insert into public.news_items (source_name, source_url, title, summary, topics, published_at, model) values
    ('ScienceDaily', 'https://www.sciencedaily.com/releases/2026/10/a.htm', 'Fresh', repeat('A neutral summary sentence. ', 3), array['sleep'], now() - interval '1 day', 'chat-model-a'),
    ('ScienceDaily', 'https://www.sciencedaily.com/releases/2026/07/b.htm', 'Old', repeat('A neutral summary sentence. ', 3), array['heart'], now() - interval '61 days', 'chat-model-a');

set local role anon;
set local request.jwt.claims to '{"role":"anon"}';
select is((select count(*)::int from public.app_articles), 1, 'anon sees published articles whose date has passed, and only those');
select is((select slug from public.app_articles), 'sleep-pressure', 'the one it sees is the published one');
select is((select count(*)::int from public.news_items), 1, 'anon sees news from the last 60 days only');
select throws_ok($$insert into public.news_items (source_name, source_url, title, summary, topics, published_at, model) values ('x', 'https://x.test/a', 't', repeat('s', 50), array['sleep'], now(), 'm')$$,
    '42501', 'anon cannot write news');
select throws_ok($$insert into public.app_articles (slug, title, topic) values ('x', 'x', 'sleep')$$,
    '42501', 'anon cannot write articles');
select throws_ok($$select public.news_ingest_tick()$$, '42501', 'anon cannot run the news tick');

reset role;
select throws_ok($$insert into public.news_items (source_name, source_url, title, summary, topics, published_at, model) values ('x', 'http://x.test/a', 't', repeat('s', 50), array['sleep'], now(), 'm')$$,
    '23514', 'a news link that is not https is refused');
select is((select count(*)::int from cron.job where jobname in ('news-ingest', 'news-items-retention')), 2,
    'the news tick and the news retention are scheduled');
select is((select (published_at is not null) from public.app_articles where slug = 'sleep-pressure'), true, 'a published article has a date');

select * from finish();
rollback;
