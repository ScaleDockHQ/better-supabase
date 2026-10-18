-- better-supabase sql: the extensions of pg_jsonschema, btree_gist, created before the schema migration that needs them.

create extension if not exists "pg_jsonschema" with schema "extensions";
create extension if not exists "btree_gist" with schema "extensions";
