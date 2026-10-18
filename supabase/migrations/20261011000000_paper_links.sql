-- Safe to run again: everything is guarded (if not exists).
-- Paper links (app schema v20): a paper's PubMed id, web link and
-- abstract, filled by lookups (Crossref, PubMed, arXiv) and imports
-- (Zotero, BibTeX, RIS).
alter table public.papers add column if not exists pmid text;
alter table public.papers add column if not exists url text;
alter table public.papers add column if not exists abstract text;
