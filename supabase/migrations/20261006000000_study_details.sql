-- Study details (app schema v15): optional species, brain regions,
-- techniques, sample size and paradigm on papers, and synthesis-matrix
-- columns bound to one of them.
alter table public.papers add column species text;
alter table public.papers add column brain_regions text;
alter table public.papers add column techniques text;
alter table public.papers add column sample_size integer;
alter table public.papers add column paradigm text;
alter table public.matrix_columns add column paper_field text;
