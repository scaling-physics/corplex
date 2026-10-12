-- Safe to run again: everything is guarded (if not exists / drop if exists).
-- Citekeys and ratings on papers, and the synthesis matrix (app schema v10).
-- Same conventions as 20260929000000_sync_schema.sql.

alter table public.papers add column if not exists citekey text;
alter table public.papers add column if not exists rating integer;

create table if not exists public.matrix_columns (
  id uuid not null,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  project_id uuid not null,
  name text not null,
  position integer not null default 0,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  synced_at timestamptz not null default clock_timestamp(),
  primary key (id)
);

create table if not exists public.matrix_cells (
  column_id uuid not null,
  paper_id uuid not null,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  text text not null default '',
  updated_at timestamptz not null,
  deleted_at timestamptz,
  synced_at timestamptz not null default clock_timestamp(),
  primary key (column_id, paper_id)
);

create index if not exists matrix_columns_user_synced_idx on public.matrix_columns (user_id, synced_at);
create index if not exists matrix_cells_user_synced_idx on public.matrix_cells (user_id, synced_at);

alter table public.matrix_columns enable row level security;
alter table public.matrix_cells enable row level security;

drop policy if exists matrix_columns_select on public.matrix_columns;
create policy matrix_columns_select on public.matrix_columns for select using (user_id = auth.uid());
drop policy if exists matrix_columns_insert on public.matrix_columns;
create policy matrix_columns_insert on public.matrix_columns for insert with check (user_id = auth.uid());
drop policy if exists matrix_columns_update on public.matrix_columns;
create policy matrix_columns_update on public.matrix_columns for update using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists matrix_cells_select on public.matrix_cells;
create policy matrix_cells_select on public.matrix_cells for select using (user_id = auth.uid());
drop policy if exists matrix_cells_insert on public.matrix_cells;
create policy matrix_cells_insert on public.matrix_cells for insert with check (user_id = auth.uid());
drop policy if exists matrix_cells_update on public.matrix_cells;
create policy matrix_cells_update on public.matrix_cells for update using (user_id = auth.uid()) with check (user_id = auth.uid());

drop trigger if exists matrix_columns_sync_guard on public.matrix_columns;
create trigger matrix_columns_sync_guard before insert or update on public.matrix_columns
  for each row execute function public.sync_guard();
drop trigger if exists matrix_cells_sync_guard on public.matrix_cells;
create trigger matrix_cells_sync_guard before insert or update on public.matrix_cells
  for each row execute function public.sync_guard();
