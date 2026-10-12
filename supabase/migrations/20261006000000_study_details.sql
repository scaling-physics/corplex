-- Safe to run again: everything is guarded (if not exists / drop if exists).
-- Study details (app schema v15): optional species, brain regions,
-- techniques, sample size and paradigm on papers, and synthesis-matrix
-- columns bound to one of them.
alter table public.papers add column if not exists species text;
alter table public.papers add column if not exists brain_regions text;
alter table public.papers add column if not exists techniques text;
alter table public.papers add column if not exists sample_size integer;
alter table public.papers add column if not exists paradigm text;
alter table public.matrix_columns add column if not exists paper_field text;
