-- Safe to run again: everything is guarded (if not exists / drop if exists).
-- Note comments (app schema v19): comments on a passage of a note, e.g. a
-- supervisor's feedback on a chapter. Same conventions as
-- 20261007000000_note_versions.sql. `resolved` is an integer 0/1, like
-- notes.pinned, because sync copies SQLite's values through unconverted.

create table if not exists public.note_comments (
  id uuid not null,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  note_id uuid not null,
  quote text not null,
  anchor integer not null default 0,
  body text not null,
  author text,
  resolved integer not null default 0,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  synced_at timestamptz not null default clock_timestamp(),
  primary key (id)
);

create index if not exists note_comments_user_synced_idx on public.note_comments (user_id, synced_at);

alter table public.note_comments enable row level security;

drop policy if exists note_comments_select on public.note_comments;
create policy note_comments_select on public.note_comments for select using (user_id = auth.uid());
drop policy if exists note_comments_insert on public.note_comments;
create policy note_comments_insert on public.note_comments for insert with check (user_id = auth.uid());
drop policy if exists note_comments_update on public.note_comments;
create policy note_comments_update on public.note_comments for update using (user_id = auth.uid()) with check (user_id = auth.uid());

drop trigger if exists note_comments_sync_guard on public.note_comments;
create trigger note_comments_sync_guard before insert or update on public.note_comments
  for each row execute function public.sync_guard();
