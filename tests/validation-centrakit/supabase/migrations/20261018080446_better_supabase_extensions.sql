-- better-supabase sql: the extensions of pgmq, pg_jsonschema, created before the schema migration that needs them.

create extension if not exists "pgmq";
create extension if not exists "pg_jsonschema" with schema "extensions";
