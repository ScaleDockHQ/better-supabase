import type { BlockSqlContext } from "../context.ts";

import {
  filterAny,
  filterFirst,
  filterHasInvalid,
  listBody,
  listDeclare,
  searchPattern,
} from "../list-template.ts";
import { fail, userGrant } from "../shared.ts";

/** What the ai-files module's `build` hands the file page function. */
export interface AiFilePageDeps {
  readonly id: string;
  /** The quoted file columns. */
  readonly f: {
    readonly id: string;
    readonly tenant: string;
    readonly chat: string;
    readonly mediaType: string;
    readonly filename: string;
    readonly size: string;
    readonly status: string;
    readonly source: string;
    readonly createdAt: string;
  };
  readonly files: string;
  readonly fileJson: (row: string) => string;
}

/** `page_ai_files`: the tenant's files as a keyset page (ADR 1077). */
export function aiFilePageSql(
  ctx: BlockSqlContext,
  deps: AiFilePageDeps,
): string {
  const { f, files, fileJson } = deps;
  const fn = (name: string): string => ctx.fn(name);
  const source = ctx.has("files", "source") ? `x.${f.source}` : "'upload'";
  const idKey = { expr: `x.${f.id}`, dir: "asc", type: "uuid" } as const;

  const oldest = [
    { expr: `x.${f.createdAt}`, dir: "asc", type: "timestamptz" },
    idKey,
  ] as const;

  const filePage = {
    name: "page_ai_files",
    from: files,
    alias: "x",
    where: [
      `x.${f.tenant} = page_ai_files.tenant`,
      `(v_chat is null or x.${f.chat} = v_chat::uuid)`,
      filterAny("status", `x.${f.status}::text`),
      filterAny("source", `${source}::text`),
      filterAny("mediaType", `x.${f.mediaType}`),
      `(v_search is null or x.${f.filename} ilike v_search)`,
    ],
    keys: oldest,
    sorts: {
      createdAt: oldest,
      filename: [
        { expr: `lower(x.${f.filename})`, dir: "asc", type: "text" },
        idKey,
      ],
      size: [{ expr: `x.${f.size}`, dir: "desc", type: "bigint" }, idKey],
    },
    facets: { status: `x.${f.status}`, source, mediaType: `x.${f.mediaType}` },
    rowJson: fileJson("x"),
    defaultLimit: 50,
    maxLimit: 200,
    invalid: (message: string) => fail("AI_FILE_INVALID", message, "22023"),
  } as const;

  return `-- The files of a tenant the caller can read as a keyset page (ADR 1077),
-- oldest first. filters is { chatId (one uuid), status, source, mediaType (a
-- value or a list), search (filename), sort (createdAt, filename, size),
-- direction, facet, count, limit, after, offset, paged, total, totalCap }.
create or replace function ${fn("page_ai_files")}(tenant ${deps.id}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_ai_files.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  v_chat text := ${filterFirst("chatId")};
  ${listDeclare(filePage)}
begin
  if ${filterHasInvalid("chatId")} then
    ${fail("AI_FILE_INVALID", "chatId is a uuid", "22023")}
  end if;
  ${listBody(filePage)}
end;
$$;
${userGrant(`${fn("page_ai_files")}(${deps.id}, jsonb)`)}`;
}
