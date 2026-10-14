-- better-supabase sql: the extensions of pgmq, vector, pgcrypto, pg_trgm, unaccent, created before the schema migration that needs them.

create extension if not exists "pgmq";
create extension if not exists "vector" with schema "extensions";
create extension if not exists "pgcrypto" with schema "extensions";
create extension if not exists "pg_trgm" with schema "extensions";
create extension if not exists "unaccent" with schema "extensions";
