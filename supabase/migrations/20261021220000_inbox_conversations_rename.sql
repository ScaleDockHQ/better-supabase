-- The inbox's `conversations` table becomes `inbox_conversations`, so the
-- messaging core can own `conversations` (ADR 0062). pg-delta can't see a
-- rename and would rebuild the table, so this migration renames it first.
alter table better_supabase.conversations rename to inbox_conversations;
alter index better_supabase.conversations_pkey rename to inbox_conversations_pkey;
