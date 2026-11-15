import type { BlockSqlContext } from "../context.ts";
import type { ListSortKey, ListTemplateOptions } from "../list-template.ts";

import {
  filterAny,
  filterHasInvalid,
  filterSet,
  listBody,
  listDeclare,
  searchPattern,
} from "../list-template.ts";
import { fail, userGrant } from "../shared.ts";
import { asText } from "./over-app.ts";

/** What the memory module's `build` hands the page function. */
export interface MemoryPageDeps {
  /** The quoted memory columns; an absent optional column is empty. */
  readonly m: Readonly<Record<string, string>>;
  readonly has: (column: string) => boolean;
  readonly memories: string;
  readonly live: (row: string) => string;
  readonly fresh: (row: string) => string;
  readonly createdAt: (row: string) => string;
  readonly memoryJson: (row: string) => string;
  /** The statements that read `ns`, check the caller and set the `v_` scope. */
  readonly namespace: (name: string) => string;
  /** The `v_` variables `namespace` sets. */
  readonly declare: string;
  readonly inNamespace: (row: string, tenant: string) => string;
}

/**
 * `page_memories` and `get_memory`: the keyset page and the read by id of the
 * block list contract (ADR 1077). The page reads one namespace as `memory_list`
 * does, and RLS decides what the caller sees.
 */
export function memoryPagesSql(
  ctx: BlockSqlContext,
  deps: MemoryPageDeps,
): string {
  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const { m, has, memories, live, fresh, createdAt, memoryJson } = deps;

  const invalid = (message: string): string =>
    fail("MEMORY_INVALID", message, "22023");

  const idKey: ListSortKey = {
    expr: `x.${m["id"]}`,
    dir: "desc",
    type: "uuid",
  };

  const kind = asText(ctx, "memories", `x.${m["kind"]}`);

  const newest: readonly ListSortKey[] = [
    { expr: createdAt("x"), dir: "desc", type: "timestamptz" },
    idKey,
  ];

  const optionalSort = (
    column: string,
    expr: string,
    type: string,
    dir: "asc" | "desc",
  ): Record<string, readonly ListSortKey[]> =>
    has(column) ? { [column]: [{ expr, dir, type }, idKey] } : {};

  const category = has("category") ? `x.${m["category"]}` : undefined;

  const page: ListTemplateOptions = {
    name: "page_memories",
    from: memories,
    alias: "x",
    where: [
      deps.inNamespace("x", "page_memories.tenant"),
      `true${fresh("x")}`,
      `(case when ${filterSet("kind")} then ${filterAny("kind", kind)} else ${kind} = 'archival' end)`,
      category === undefined
        ? "true"
        : filterAny("category", `coalesce(${category}, '')`),
      `(v_search is null or x.${m["content"]} ilike v_search)`,
    ],
    keys: newest,
    sorts: {
      createdAt: newest,
      updatedAt: [
        { expr: `x.${m["updatedAt"]}`, dir: "desc", type: "timestamptz" },
        idKey,
      ],
      path: [
        { expr: `coalesce(x.${m["path"]}, '')`, dir: "asc", type: "text" },
        idKey,
      ],
      ...optionalSort("useCount", `x.${m["useCount"]}`, "integer", "desc"),
      ...optionalSort(
        "lastUsedAt",
        `coalesce(x.${m["lastUsedAt"]}, 'epoch'::timestamptz)`,
        "timestamptz",
        "desc",
      ),
    },
    facets: {
      kind,
      ...(category === undefined
        ? {}
        : { category: `coalesce(${category}, '')` }),
    },
    rowJson: memoryJson("x"),
    defaultLimit: 50,
    maxLimit: 200,
    invalid,
  };

  return `-- The memories of one namespace as a keyset page (ADR 1077), archival facts
-- newest first. ns names the namespace as memory_list does. filters is { kind
-- (core, archival; archival by default), category (a value or a list), search
-- (content), sort (createdAt, updatedAt, path${has("useCount") ? ", useCount" : ""}${has("lastUsedAt") ? ", lastUsedAt" : ""}), direction, facet,
-- count, limit, after, offset, paged, total, totalCap }. It runs as the
-- caller: row level security decides what shows.
create or replace function ${fn("page_memories")}(tenant ${id}, ns jsonb default '{}', filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare${deps.declare}
  v_filters jsonb := coalesce(page_memories.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  ${listDeclare(page)}
begin${deps.namespace("page_memories")}
  if ${filterHasInvalid("kind", ["core", "archival"])} then
    ${invalid("kind is core or archival")}
  end if;
  ${listBody(page)}
end;
$$;
${userGrant(`${fn("page_memories")}(${id}, jsonb, jsonb)`)}

-- One memory the caller can read by id, or null.
create or replace function ${fn("get_memory")}(memory_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${memoryJson("x")} from ${memories} x
  where x.${m["id"]} = get_memory.memory_id${live("x")}
$$;
${userGrant(`${fn("get_memory")}(uuid)`)}`;
}
