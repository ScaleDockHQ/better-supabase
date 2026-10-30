-- better-supabase upgrade: steps that run before the schema diff.

-- knowledge: version 4 to 5. Collection grants gain the collection's tenant (organization_id, filled from the collection), and team_id takes the teams id type when teams is installed.
alter table "better_supabase"."knowledge_collection_grants" add column if not exists "organization_id" uuid;
update "better_supabase"."knowledge_collection_grants" x set "organization_id" = c."organization_id"
from "better_supabase"."knowledge_collections" c
where c."id" = x."collection_id" and x."organization_id" is null;
alter table "better_supabase"."knowledge_collection_grants" alter column "team_id" type uuid using "team_id"::uuid;

-- memory: version 3 to 4. Organization and record memory may have an owner (ns.private), options.tenant: false lets personal memory have no tenant, options.maxItems caps archival facts, and purge_memories takes a tenant.
alter table "better_supabase"."memories" drop constraint if exists memories_owner_check;
alter table "better_supabase"."memories" add constraint memories_owner_check check ("scope" in ('organization', 'record') or "owner_id" is not null);
