-- File sync: PDFs and attachment files live in a private Storage bucket,
-- one folder per user, and the rows point at them via storage_key.
--
-- Object keys look like  <user_id>/papers/<paper_id>.pdf  and
-- <user_id>/attachments/<attachment_id>.<ext>. The first path segment must
-- equal the caller's user id, which is what the policies below enforce.

alter table public.papers add column storage_key text;
alter table public.attachments add column storage_key text;

insert into storage.buckets (id, name, public)
values ('files', 'files', false)
on conflict (id) do nothing;

create policy files_select on storage.objects for select to authenticated
  using (bucket_id = 'files' and (storage.foldername(name))[1] = auth.uid()::text);

create policy files_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'files' and (storage.foldername(name))[1] = auth.uid()::text);

-- Uploads use upsert (a retried upload must not fail), which needs update.
create policy files_update on storage.objects for update to authenticated
  using (bucket_id = 'files' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'files' and (storage.foldername(name))[1] = auth.uid()::text);

create policy files_delete on storage.objects for delete to authenticated
  using (bucket_id = 'files' and (storage.foldername(name))[1] = auth.uid()::text);
