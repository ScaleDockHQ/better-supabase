---
"better-supabase": minor
---

Knowledge collection grants keep their collection's tenant and type `team_id` with the teams id type, and `visibility` may be an enum on an adopted `knowledge_collections` table. Memory gains private organization and record memory, personal memory without a tenant, a cap on archival facts and a per-tenant purge.

- `knowledge_collection_grants` gains `organization_id`, filled from the collection, so data lifecycle exports and deletes grants with the tenant. With the `teams` block installed, `team_id` takes the teams id type (`uuid` by default) and `set_knowledge_collection_grant` takes a team id of that type. `better-supabase upgrade` writes the column change for an existing install:

  ```sql
  alter table better_supabase.knowledge_collection_grants add column if not exists organization_id uuid;
  update better_supabase.knowledge_collection_grants x set organization_id = c.organization_id
  from better_supabase.knowledge_collections c where c.id = x.collection_id;
  alter table better_supabase.knowledge_collection_grants alter column team_id type uuid using team_id::uuid;
  ```

  An adopted grants table needs the `organization_id` column too.

- `knowledge_collections.visibility` is listed in `typed`: an adopted table may declare it as an enum, written and compared through the column's type and `blocks.knowledge.values`.
- A memory namespace takes `private: true` for `organization` and `record` scopes: the memory gets an owner, who reads and changes it without the manage permission, and nobody else reads it. The owner check constraint allows an owner on those scopes.
- `blocks.memory.options.tenant: false` lets personal memory have no tenant: pass `null` as the organization. `MemoryRecord.organizationId` is `string | null`.
- `blocks.memory.options.maxItems` keeps at most that many archival facts per owner (or shared namespace pool) in a tenant; saving one more forgets the oldest.
- `purge_memories` takes a `tenant` (`archival.purge({ organizationId })`) to purge one tenant. The two-argument function is dropped.
