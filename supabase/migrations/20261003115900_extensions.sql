-- Extensions the app project needs, before anything uses them.
-- pg_cron: the nightly tombstone purge (sync foundation), the news tick and
-- the news retention job. pg_net: the news tick's call to its Edge Function.
-- Supabase installs both into the schemas they expect (cron and net).
create extension if not exists pg_cron;
create extension if not exists pg_net;
