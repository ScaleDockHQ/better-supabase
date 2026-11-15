import type { BlockSqlContext } from "../context.ts";

import {
  filterAny,
  filterFlag,
  listBody,
  listDeclare,
  searchPattern,
} from "../list-template.ts";
import { fail, userGrant } from "../shared.ts";
import { packsOn } from "./custom-fields-packs.ts";

/** The JSON of definition row `alias`, as `list_field_definitions` returns it. */
function definitionJson(
  ctx: BlockSqlContext,
  alias: string,
  rank: string,
): string {
  const archivable = ctx.has("definitions", "archivedAt");

  return `jsonb_build_object(
    'id', ${alias}.${ctx.col("definitions", "id")},
    'entity', ${alias}.${ctx.col("definitions", "entity")},
    'key', ${alias}.${ctx.col("definitions", "key")},
    'label', ${alias}.${ctx.col("definitions", "label")},
    'type', ${alias}.${ctx.col("definitions", "type")},
    'required', ${alias}.${ctx.col("definitions", "required")},
    'sensitive', ${alias}.${ctx.col("definitions", "sensitive")},${
      ctx.has("definitions", "encrypted")
        ? `
    'encrypted', ${alias}.${ctx.col("definitions", "encrypted")},`
        : ""
    }
    ${
      packsOn(ctx)
        ? `'pack', ${alias}.${ctx.col("definitions", "pack")},
    'packVersion', ${alias}.${ctx.col("definitions", "packVersion")},
    `
        : ""
    }${archivable ? `'archivedAt', ${alias}.${ctx.col("definitions", "archivedAt")},\n    ` : ""}'rank', ${rank === "" ? "null" : `${alias}.${rank}`}
  )`;
}

export function listDefinitions(
  ctx: BlockSqlContext,
  definitions: string,
  rank: string,
  read: string,
): string {
  const archivable = ctx.has("definitions", "archivedAt");

  const order =
    rank === ""
      ? `d.${ctx.col("definitions", "key")}`
      : `d.${rank} collate "C", d.${ctx.col("definitions", "key")}`;

  const key = {
    expr: `d.${ctx.col("definitions", "id")}`,
    dir: "asc",
    type: "uuid",
  } as const;

  const byKey = [
    { expr: `d.${ctx.col("definitions", "entity")}`, dir: "asc", type: "text" },
    { expr: `d.${ctx.col("definitions", "key")}`, dir: "asc", type: "text" },
    key,
  ] as const;

  const byRank = [
    { expr: `d.${ctx.col("definitions", "entity")}`, dir: "asc", type: "text" },
    { expr: `d.${rank} collate "C"`, dir: "asc", type: "text" },
    { expr: `d.${ctx.col("definitions", "key")}`, dir: "asc", type: "text" },
    key,
  ] as const;

  const pageSpec = {
    name: "page_field_definitions",
    from: definitions,
    alias: "d",
    where: [
      `d.${ctx.col("definitions", "tenant")} = page_field_definitions.tenant`,
      filterAny("entity", `d.${ctx.col("definitions", "entity")}`),
      filterAny("type", `d.${ctx.col("definitions", "type")}::text`),
      `(not ${filterFlag("sensitive")} or d.${ctx.col("definitions", "sensitive")})`,
      archivable
        ? `(${filterFlag("archived")} or d.${ctx.col("definitions", "archivedAt")} is null)`
        : "true",
      `(v_search is null or d.${ctx.col("definitions", "key")} ilike v_search or d.${ctx.col("definitions", "label")} ilike v_search)`,
    ],
    keys: rank === "" ? byKey : byRank,
    sorts: {
      key: byKey,
      label: [
        {
          expr: `lower(d.${ctx.col("definitions", "label")})`,
          dir: "asc",
          type: "text",
        },
        key,
      ],
      type: [
        {
          expr: `d.${ctx.col("definitions", "type")}::text`,
          dir: "asc",
          type: "text",
        },
        key,
      ],
      ...(rank === "" ? {} : { rank: byRank }),
    },
    facets: {
      entity: `d.${ctx.col("definitions", "entity")}`,
      type: `d.${ctx.col("definitions", "type")}::text`,
    },
    rowJson: definitionJson(ctx, "d", rank),
    defaultLimit: 50,
    maxLimit: 200,
    invalid: (message: string) =>
      fail("CUSTOM_FIELD_INVALID", message, "22023"),
  } as const;

  return `
-- The definitions of one entity in display order. Archived fields stay out
-- unless include_archived is true.${archivable ? `\ndrop function if exists ${ctx.fn("list_field_definitions")}(${ctx.idType}, text);` : ""}
create or replace function ${ctx.fn("list_field_definitions")}(tenant ${ctx.idType}, entity text${archivable ? ", include_archived boolean default false" : ""})
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(${definitionJson(ctx, "d", rank)} order by ${order}), '[]'::jsonb)
  from ${definitions} d
  where d.${ctx.col("definitions", "tenant")} = list_field_definitions.tenant
    and d.${ctx.col("definitions", "entity")} = list_field_definitions.entity${archivable ? `\n    and (coalesce(list_field_definitions.include_archived, false) or d.${ctx.col("definitions", "archivedAt")} is null)` : ""}
    and (auth.role() = 'service_role' or ${ctx.scope.can("list_field_definitions.tenant", read)})
$$;
${userGrant(`${ctx.fn("list_field_definitions")}(${ctx.idType}, text${archivable ? ", boolean" : ""})`)}

-- One entity's definitions as a keyset page in display order (ADR 1077).
-- filters is { entity, type (each a value or a list), sensitive (true keeps
-- sensitive fields), archived (true adds archived fields), search (key,
-- label), sort (key, label, type\${rank === "" ? "" : ", rank"}), direction, facet, count, limit, after,
-- offset, paged, total, totalCap }.
create or replace function ${ctx.fn("page_field_definitions")}(tenant ${ctx.idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_field_definitions.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  ${listDeclare(pageSpec)}
begin
  if not (auth.role() = 'service_role' or ${ctx.scope.can("page_field_definitions.tenant", read)}) then
    ${fail("CUSTOM_FIELD_FORBIDDEN", "not allowed to read custom fields")}
  end if;
  ${listBody(pageSpec)}
end;
$$;
${userGrant(`${ctx.fn("page_field_definitions")}(${ctx.idType}, jsonb)`)}

-- One definition the caller may read, or null.
create or replace function ${ctx.fn("get_field_definition")}(id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${definitions}%rowtype;
begin
  select * into v_row from ${definitions} d where d.${ctx.col("definitions", "id")} = get_field_definition.id;
  if not found then
    return null;
  end if;
  if not (auth.role() = 'service_role' or ${ctx.scope.can(`v_row.${ctx.col("definitions", "tenant")}`, read)}) then
    ${fail("CUSTOM_FIELD_FORBIDDEN", "not allowed to read custom fields")}
  end if;
  return ${definitionJson(ctx, "v_row", rank)};
end;
$$;
${userGrant(`${ctx.fn("get_field_definition")}(uuid)`)}
`;
}
