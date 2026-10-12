-- Thesis outline (app schema v14): chapter order, status and word target on
-- a project's notes, and a submission date on projects.
alter table public.project_notes add column position integer;
alter table public.project_notes add column status text;
alter table public.project_notes add column word_target integer;
alter table public.projects add column due_date timestamptz;
