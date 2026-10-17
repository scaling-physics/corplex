-- Safe to run again: everything is guarded (if not exists / drop if exists).
-- Locked notes (app schema v17): the notes password as wrapped keys. Each
-- row holds a random notes key encrypted under a key derived from the
-- user's notes password (PBKDF2), so the server stores only ciphertext:
-- neither the password nor the key ever reaches it. Locked note bodies sync
-- through the existing notes.content / note_versions.content columns as an
-- encrypted envelope. Same conventions as 20261002000000_projects.sql.

create table if not exists public.note_keys (
  id uuid not null,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  kdf text not null,
  iterations integer not null,
  salt text not null,
  wrapped_key text not null,
  hint text,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  synced_at timestamptz not null default clock_timestamp(),
  primary key (id)
);

create index if not exists note_keys_user_synced_idx on public.note_keys (user_id, synced_at);

alter table public.note_keys enable row level security;

drop policy if exists note_keys_select on public.note_keys;
create policy note_keys_select on public.note_keys for select using (user_id = auth.uid());
drop policy if exists note_keys_insert on public.note_keys;
create policy note_keys_insert on public.note_keys for insert with check (user_id = auth.uid());
drop policy if exists note_keys_update on public.note_keys;
create policy note_keys_update on public.note_keys for update using (user_id = auth.uid()) with check (user_id = auth.uid());

drop trigger if exists note_keys_sync_guard on public.note_keys;
create trigger note_keys_sync_guard before insert or update on public.note_keys
  for each row execute function public.sync_guard();
