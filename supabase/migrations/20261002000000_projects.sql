-- Projects: named groups of papers and notes (app schema v8).
-- Same conventions as 20260929000000_sync_schema.sql.

create table public.projects (
  id uuid not null,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  synced_at timestamptz not null default clock_timestamp(),
  primary key (id)
);

create table public.project_papers (
  project_id uuid not null,
  paper_id uuid not null,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  synced_at timestamptz not null default clock_timestamp(),
  primary key (project_id, paper_id)
);

create table public.project_notes (
  project_id uuid not null,
  note_id uuid not null,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  synced_at timestamptz not null default clock_timestamp(),
  primary key (project_id, note_id)
);

create index projects_user_synced_idx on public.projects (user_id, synced_at);
create index project_papers_user_synced_idx on public.project_papers (user_id, synced_at);
create index project_notes_user_synced_idx on public.project_notes (user_id, synced_at);

alter table public.projects enable row level security;
alter table public.project_papers enable row level security;
alter table public.project_notes enable row level security;

create policy projects_select on public.projects for select using (user_id = auth.uid());
create policy projects_insert on public.projects for insert with check (user_id = auth.uid());
create policy projects_update on public.projects for update using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy project_papers_select on public.project_papers for select using (user_id = auth.uid());
create policy project_papers_insert on public.project_papers for insert with check (user_id = auth.uid());
create policy project_papers_update on public.project_papers for update using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy project_notes_select on public.project_notes for select using (user_id = auth.uid());
create policy project_notes_insert on public.project_notes for insert with check (user_id = auth.uid());
create policy project_notes_update on public.project_notes for update using (user_id = auth.uid()) with check (user_id = auth.uid());

create trigger projects_sync_guard before insert or update on public.projects
  for each row execute function public.sync_guard();
create trigger project_papers_sync_guard before insert or update on public.project_papers
  for each row execute function public.sync_guard();
create trigger project_notes_sync_guard before insert or update on public.project_notes
  for each row execute function public.sync_guard();
