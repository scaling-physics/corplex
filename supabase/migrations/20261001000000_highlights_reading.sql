-- Text highlights, and per-paper reading position/status (app schema v7).
-- Same conventions as 20260929000000_sync_schema.sql.

alter table public.papers add column last_page integer;
alter table public.papers add column reading_status text;

create table public.highlights (
  id uuid not null,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  paper_id uuid not null,
  page_number integer not null,
  quote text not null,
  rects_json text not null,
  color_hex text not null,
  comment text,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  synced_at timestamptz not null default clock_timestamp(),
  primary key (id)
);
create index highlights_user_synced_idx on public.highlights (user_id, synced_at);
alter table public.highlights enable row level security;
create policy highlights_select on public.highlights for select using (user_id = auth.uid());
create policy highlights_insert on public.highlights for insert with check (user_id = auth.uid());
create policy highlights_update on public.highlights for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create trigger highlights_sync_guard before insert or update on public.highlights
  for each row execute function public.sync_guard();
