-- Columns the blocks add to centrakit.organization_number_sequences, declared in your schema.
-- better-supabase upgrade never rewrites this file.

alter table "centrakit"."organization_number_sequences" add column if not exists "scope" text not null default '';
