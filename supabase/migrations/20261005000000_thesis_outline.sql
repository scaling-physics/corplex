-- Safe to run again: everything is guarded (if not exists / drop if exists).
-- Thesis outline (app schema v14): chapter order, status and word target on
-- a project's notes, and a submission date on projects.
alter table public.project_notes add column if not exists position integer;
alter table public.project_notes add column if not exists status text;
alter table public.project_notes add column if not exists word_target integer;
alter table public.projects add column if not exists due_date timestamptz;
