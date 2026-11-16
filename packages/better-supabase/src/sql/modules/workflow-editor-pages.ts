import type { BuilderSql } from "./workflow-editor-sql.ts";

import {
  filterAny,
  listBody,
  listDeclare,
  searchPattern,
} from "../list-template.ts";
import { fail } from "../shared.ts";

/**
 * `page_workflow_definitions`: the keyset page, facet counts and count behind
 * `definitions.page` (ADR 1077). It reads the rows `workflow_definitions_list`
 * reads, so a system definition is visible to a tenant that asks for its own.
 */
export function definitionPageSql(s: BuilderSql): string {
  const { id, fn, d, v, cd, cv, definitionJson, optedOut, callable } = s;
  const { scoped, forked } = s;

  const published = `(select y.${cv("version")} from ${v} y where y.${cv("definition")} = x.${cd("id")} and y.${cv("status")} = 'published')`;
  const draft = `exists (select 1 from ${v} y where y.${cv("definition")} = x.${cd("id")} and y.${cv("status")} = 'draft')`;
  const state = `(case when ${published} is not null then 'published' when ${draft} then 'draft' else 'new' end)`;
  const idKey = { expr: `x.${cd("id")}`, dir: "asc", type: "uuid" } as const;
  const name = { expr: `x.${cd("name")}`, dir: "asc", type: "text" } as const;

  const updated = {
    expr: `x.${cd("updatedAt")}`,
    dir: "desc",
    type: "timestamptz",
  } as const;

  const created = {
    expr: `x.${cd("createdAt")}`,
    dir: "desc",
    type: "timestamptz",
  } as const;

  const upstream = forked
    ? `(select y.${cv("version")} from ${v} y where y.${cv("definition")} = x.${cd("forkedFrom")} and y.${cv("status")} = 'published')`
    : "null";

  const page = {
    name: "page_workflow_definitions",
    from: d,
    alias: "x",
    where: [
      `(page_workflow_definitions.tenant is null or x.${cd("tenant")} = page_workflow_definitions.tenant${scoped ? ` or x.${cd("scope")} = 'system'` : ""})`,
      filterAny("state", state),
      `(v_search is null or x.${cd("name")} ilike v_search or x.${cd("slug")} ilike v_search)`,
    ],
    keys: [name, idKey],
    sorts: {
      name: [name, idKey],
      updatedAt: [updated, idKey],
      createdAt: [created, idKey],
    },
    facets: { state },
    rowJson: `${definitionJson("x")} || jsonb_build_object(
      'published', ${published},
      'draft', ${draft},
      'upstreamVersion', ${upstream},
      'behind', ${forked ? `coalesce(${upstream} > x.${cd("forkedFromVersion")}, false)` : "false"},
      'optedOut', case when page_workflow_definitions.tenant is null then null else ${optedOut(`x.${cd("id")}`, "page_workflow_definitions.tenant")} end)`,
    defaultLimit: 50,
    maxLimit: 200,
    invalid: (message: string) =>
      fail("WORKFLOW_LIST_INVALID", message, "22023"),
  } as const;

  return `-- The definitions the caller may read as a keyset page (ADR 1077), by name.
-- filters is { state (published, draft or new; a value or a list), search
-- (name and slug), sort (name, updatedAt, createdAt), direction, facet
-- (state), count, limit, after, offset, paged, total, totalCap }. With
-- tenant, the tenant's definitions and the system ones, as
-- workflow_definitions_list returns them.
create or replace function ${fn("page_workflow_definitions")}(tenant ${id} default null, filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_workflow_definitions.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  ${listDeclare(page)}
begin
  ${listBody(page)}
end;
$$;
${callable(`${fn("page_workflow_definitions")}(${id}, jsonb)`)}`;
}
