-- Safe to run again: everything is guarded (if not exists / drop if exists).
-- Note versions (app schema v16): saved copies of a note, e.g. a chapter
-- sent to a supervisor. Same conventions as 20261002000000_projects.sql.

create table if not exists public.note_versions (
  id uuid not null,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  note_id uuid not null,
  title text not null,
  content text not null,
  label text,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  synced_at timestamptz not null default clock_timestamp(),
  primary key (id)
);

create index if not exists note_versions_user_synced_idx on public.note_versions (user_id, synced_at);

alter table public.note_versions enable row level security;

drop policy if exists note_versions_select on public.note_versions;
create policy note_versions_select on public.note_versions for select using (user_id = auth.uid());
drop policy if exists note_versions_insert on public.note_versions;
create policy note_versions_insert on public.note_versions for insert with check (user_id = auth.uid());
drop policy if exists note_versions_update on public.note_versions;
create policy note_versions_update on public.note_versions for update using (user_id = auth.uid()) with check (user_id = auth.uid());

drop trigger if exists note_versions_sync_guard on public.note_versions;
create trigger note_versions_sync_guard before insert or update on public.note_versions
  for each row execute function public.sync_guard();
