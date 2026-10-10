-- Page count of a paper's PDF, for reading progress (app schema v12).
alter table public.papers add column page_count integer;
