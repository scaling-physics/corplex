-- Safe to run again: guarded with "if not exists".
-- Pinned notes (app schema v18): pinned notes sit at the top of the list.
-- An integer 0/1, not boolean: the app stores it as SQLite does, and sync
-- copies values through unchanged.
alter table public.notes add column if not exists pinned integer not null default 0;
