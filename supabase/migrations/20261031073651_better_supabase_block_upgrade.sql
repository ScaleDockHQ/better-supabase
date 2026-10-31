-- better-supabase upgrade: steps that run before the schema diff.

-- custom-fields: version 3 to 4. Field definitions name a registered subject type (FIELD_ENTITY_UNKNOWN), carry the field pack they came from, and install_field_pack installs a pack idempotently; blocks.custom-fields.options.entityMap renames stored entities, and with the legal-entities block field_values gain a nullable legal_entity_id.
alter table "better_supabase"."field_definitions" add column if not exists "pack" text;
alter table "better_supabase"."field_definitions" add column if not exists "pack_version" integer;
