-- better-supabase sql: the extensions of pgcrypto, created before the schema migration that needs them.

create extension if not exists "pgcrypto" with schema "extensions";
