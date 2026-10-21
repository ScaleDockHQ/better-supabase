-- better-supabase module: reactions
-- @bs-module-data reactions
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Copies the reactions inbox messages kept in their jsonb column, without
-- recording them as new reactions.
select set_config('better_supabase.bs_reactions_backfill', 'on', true);
insert into "better_supabase"."reactions" ("tenant_id", "subject_type", "subject_id", "actor", "user_id", "emoji")
select m."tenant_id", 'inbox_message', m."id"::text, a.actor,
  case when a.actor ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then a.actor::uuid end,
  e.key
from "better_supabase"."inbox_messages" m
cross join lateral jsonb_each(case when jsonb_typeof(m."reactions") = 'object' then m."reactions" else '{}'::jsonb end) e
cross join lateral jsonb_array_elements_text(case when jsonb_typeof(e.value) = 'array' then e.value else '[]'::jsonb end) a(actor)
where length(e.key) between 1 and 64 and e.key !~ '\s' and e.key !~ '^:[a-z0-9_+-]{1,32}:$'
on conflict do nothing;
select set_config('better_supabase.bs_reactions_backfill', '', true);

insert into better_supabase.modules (name, version, mode)
values ('reactions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
