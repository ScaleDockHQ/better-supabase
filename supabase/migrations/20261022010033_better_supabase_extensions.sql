-- better-supabase sql: the extensions of postgis, created before the schema migration that needs them.

create extension if not exists "postgis" with schema "extensions";
