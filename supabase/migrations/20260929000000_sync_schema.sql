-- Corplex cloud sync schema.
--
-- Mirrors the local drift tables (lib/data/tables/) column for column, using
-- the same snake_case names, so the app's sync engine
-- (lib/features/sync/sync_engine.dart) can move rows without translation.
-- Local-only columns (papers.pdf_path, attachments.path) are deliberately
-- absent: file paths mean nothing on another device.
--
-- Per table, beyond the mirrored columns:
--   user_id     owner; defaults to the caller and is enforced by RLS.
--   deleted_at  soft delete, so deletes reach devices that were offline.
--   synced_at   server clock, set on every accepted write; devices pull
--               "changed since" this, which is immune to device clock skew.
--
-- Conflicts are last-write-wins on the client-supplied updated_at: a write
-- older than the stored row is ignored (see sync_guard below).
--
-- No foreign keys between tables: a sync must never wedge on one row whose
-- parent hasn't arrived. Ownership is guaranteed by RLS instead.

create function public.sync_guard() returns trigger
language plpgsql
security invoker
as $$
begin
  if tg_op = 'UPDATE' then
    new.user_id := old.user_id;
    if new.updated_at < old.updated_at then
      return old;  -- stale write: keep the newer row untouched
    end if;
  end if;
  new.synced_at := clock_timestamp();
  return new;
end;
$$;

create table public.folders (
  id uuid not null,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  synced_at timestamptz not null default clock_timestamp(),
  primary key (id)
);
create index folders_user_synced_idx on public.folders (user_id, synced_at);
alter table public.folders enable row level security;
create policy folders_select on public.folders for select using (user_id = auth.uid());
create policy folders_insert on public.folders for insert with check (user_id = auth.uid());
create policy folders_update on public.folders for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create trigger folders_sync_guard before insert or update on public.folders
  for each row execute function public.sync_guard();

create table public.tags (
  id uuid not null,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  synced_at timestamptz not null default clock_timestamp(),
  primary key (id)
);
create index tags_user_synced_idx on public.tags (user_id, synced_at);
alter table public.tags enable row level security;
create policy tags_select on public.tags for select using (user_id = auth.uid());
create policy tags_insert on public.tags for insert with check (user_id = auth.uid());
create policy tags_update on public.tags for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create trigger tags_sync_guard before insert or update on public.tags
  for each row execute function public.sync_guard();

create table public.papers (
  id uuid not null,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title text not null,
  authors text not null,
  year integer,
  venue text,
  doi text,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  synced_at timestamptz not null default clock_timestamp(),
  primary key (id)
);
create index papers_user_synced_idx on public.papers (user_id, synced_at);
alter table public.papers enable row level security;
create policy papers_select on public.papers for select using (user_id = auth.uid());
create policy papers_insert on public.papers for insert with check (user_id = auth.uid());
create policy papers_update on public.papers for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create trigger papers_sync_guard before insert or update on public.papers
  for each row execute function public.sync_guard();

create table public.notes (
  id uuid not null,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  title text not null,
  content text not null,
  folder_id uuid,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  synced_at timestamptz not null default clock_timestamp(),
  primary key (id)
);
create index notes_user_synced_idx on public.notes (user_id, synced_at);
alter table public.notes enable row level security;
create policy notes_select on public.notes for select using (user_id = auth.uid());
create policy notes_insert on public.notes for insert with check (user_id = auth.uid());
create policy notes_update on public.notes for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create trigger notes_sync_guard before insert or update on public.notes
  for each row execute function public.sync_guard();

create table public.note_tags (
  note_id uuid not null,
  tag_id uuid not null,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  synced_at timestamptz not null default clock_timestamp(),
  primary key (note_id, tag_id)
);
create index note_tags_user_synced_idx on public.note_tags (user_id, synced_at);
alter table public.note_tags enable row level security;
create policy note_tags_select on public.note_tags for select using (user_id = auth.uid());
create policy note_tags_insert on public.note_tags for insert with check (user_id = auth.uid());
create policy note_tags_update on public.note_tags for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create trigger note_tags_sync_guard before insert or update on public.note_tags
  for each row execute function public.sync_guard();

create table public.note_paper_refs (
  note_id uuid not null,
  paper_id uuid not null,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  synced_at timestamptz not null default clock_timestamp(),
  primary key (note_id, paper_id)
);
create index note_paper_refs_user_synced_idx on public.note_paper_refs (user_id, synced_at);
alter table public.note_paper_refs enable row level security;
create policy note_paper_refs_select on public.note_paper_refs for select using (user_id = auth.uid());
create policy note_paper_refs_insert on public.note_paper_refs for insert with check (user_id = auth.uid());
create policy note_paper_refs_update on public.note_paper_refs for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create trigger note_paper_refs_sync_guard before insert or update on public.note_paper_refs
  for each row execute function public.sync_guard();

create table public.attachments (
  id uuid not null,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  note_id uuid,
  paper_id uuid,
  type text not null,
  title text,
  url text,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  synced_at timestamptz not null default clock_timestamp(),
  primary key (id)
);
create index attachments_user_synced_idx on public.attachments (user_id, synced_at);
alter table public.attachments enable row level security;
create policy attachments_select on public.attachments for select using (user_id = auth.uid());
create policy attachments_insert on public.attachments for insert with check (user_id = auth.uid());
create policy attachments_update on public.attachments for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create trigger attachments_sync_guard before insert or update on public.attachments
  for each row execute function public.sync_guard();

create table public.annotations (
  id uuid not null,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  paper_id uuid not null,
  page_number integer not null,
  color_hex text not null,
  points_json text not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  synced_at timestamptz not null default clock_timestamp(),
  primary key (id)
);
create index annotations_user_synced_idx on public.annotations (user_id, synced_at);
alter table public.annotations enable row level security;
create policy annotations_select on public.annotations for select using (user_id = auth.uid());
create policy annotations_insert on public.annotations for insert with check (user_id = auth.uid());
create policy annotations_update on public.annotations for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create trigger annotations_sync_guard before insert or update on public.annotations
  for each row execute function public.sync_guard();
