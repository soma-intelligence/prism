-- Storage: two private buckets, one folder per person.
--
-- avatars: the profile picture, at '<user id>/avatar.jpg'. 5 MB, JPEG, PNG or
-- HEIC. The app makes a 512 pixel JPEG, well under the limit.
-- health-uploads: bulk Health exports and data files (an "Export my data"
-- archive, NDJSON batches), under '<user id>/<folder>/<file>'. 200 MB per
-- object; a hosted project also caps uploads globally (Storage settings),
-- which must be raised to at least this for the largest files to pass.
--
-- Research captures do not come here: they go to separate storage, as before.
--
-- Policies: a signed in person reads, writes, replaces and deletes objects
-- whose first folder is their own user id, in these two buckets only. Nobody
-- else, anon included, sees anything. The service role bypasses them.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
    ('avatars', 'avatars', false, 5242880, array['image/jpeg', 'image/png', 'image/heic']),
    ('health-uploads', 'health-uploads', false, 209715200,
        array['application/json', 'text/csv', 'application/zip', 'application/x-ndjson', 'application/gzip'])
on conflict (id) do update set
    public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy "avatars: read own folder" on storage.objects
for select to authenticated
using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid()::text));

create policy "avatars: add to own folder" on storage.objects
for insert to authenticated
with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid()::text));

create policy "avatars: replace in own folder" on storage.objects
for update to authenticated
using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid()::text))
with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid()::text));

create policy "avatars: delete from own folder" on storage.objects
for delete to authenticated
using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid()::text));

create policy "health-uploads: read own folder" on storage.objects
for select to authenticated
using (bucket_id = 'health-uploads' and (storage.foldername(name))[1] = (select auth.uid()::text));

create policy "health-uploads: add to own folder" on storage.objects
for insert to authenticated
with check (bucket_id = 'health-uploads' and (storage.foldername(name))[1] = (select auth.uid()::text));

create policy "health-uploads: replace in own folder" on storage.objects
for update to authenticated
using (bucket_id = 'health-uploads' and (storage.foldername(name))[1] = (select auth.uid()::text))
with check (bucket_id = 'health-uploads' and (storage.foldername(name))[1] = (select auth.uid()::text));

create policy "health-uploads: delete from own folder" on storage.objects
for delete to authenticated
using (bucket_id = 'health-uploads' and (storage.foldername(name))[1] = (select auth.uid()::text));
