-- Safe to run again: everything is guarded (if not exists / drop if exists).
-- Page count of a paper's PDF, for reading progress (app schema v12).
alter table public.papers add column if not exists page_count integer;
