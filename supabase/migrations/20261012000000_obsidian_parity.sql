-- Safe to run again: everything is guarded (if not exists / drop if exists).
-- Obsidian parity (app schema v22): daily notes, note aliases and templates
-- on notes, and saved searches. `is_template` is an integer 0/1, like
-- notes.pinned, because sync copies SQLite's values through unconverted.

alter table public.notes add column if not exists daily_date text;
alter table public.notes add column if not exists aliases text;
alter table public.notes add column if not exists is_template integer not null default 0;

create table if not exists public.saved_searches (
  id uuid not null,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null,
  query text not null,
  position integer,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  synced_at timestamptz not null default clock_timestamp(),
  primary key (id)
);

create index if not exists saved_searches_user_synced_idx on public.saved_searches (user_id, synced_at);

alter table public.saved_searches enable row level security;

drop policy if exists saved_searches_select on public.saved_searches;
create policy saved_searches_select on public.saved_searches for select using (user_id = auth.uid());
drop policy if exists saved_searches_insert on public.saved_searches;
create policy saved_searches_insert on public.saved_searches for insert with check (user_id = auth.uid());
drop policy if exists saved_searches_update on public.saved_searches;
create policy saved_searches_update on public.saved_searches for update using (user_id = auth.uid()) with check (user_id = auth.uid());

drop trigger if exists saved_searches_sync_guard on public.saved_searches;
create trigger saved_searches_sync_guard before insert or update on public.saved_searches
  for each row execute function public.sync_guard();
