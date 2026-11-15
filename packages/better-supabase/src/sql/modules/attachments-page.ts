import type { BlockSqlContext } from "../context.ts";
import type { authorLookup } from "./authors.ts";

import {
  filterAny,
  filterFirst,
  listBody,
  listDeclare,
  searchPattern,
} from "../list-template.ts";
import { fail, withExtraFields } from "../shared.ts";

/** What `attachmentPageSql` reads from the attachments module. */
export interface AttachmentPageParts {
  readonly authors: ReturnType<typeof authorLookup>;
  readonly extras: ReturnType<BlockSqlContext["extraColumns"]>;
  /** The row's JSON, before the extra columns and the uploader. */
  readonly json: (row: string) => string;
}

/**
 * The block list contract (ADR 1077) for files: the keyset `page_attachments`
 * function with `q`, sorts, list filters, facets and a count. A page that names
 * a subject type and a subject id writes the same read-log entry as
 * `list_attachments`.
 */
export function attachmentPageSql(
  ctx: BlockSqlContext,
  { authors, extras, json }: AttachmentPageParts,
): string {
  const id = ctx.idType;
  const t = ctx.table("attachments");
  const c = (logical: string): string => ctx.col("attachments", logical);
  const fn = (name: string): string => ctx.fn(name);
  const has = (logical: string): boolean => ctx.has("attachments", logical);
  const rowJson = json;

  const attachmentIdKey = {
    expr: `x.${c("id")}`,
    dir: "asc",
    type: "uuid",
  } as const;

  const newestKeys = [
    { expr: `x.${c("createdAt")}`, dir: "desc", type: "timestamptz" },
    attachmentIdKey,
  ] as const;

  const attachmentPage = {
    name: "page_attachments",
    from: t,
    alias: "x",
    where: [
      `x.${c("tenant")} is not distinct from page_attachments.tenant`,
      filterAny("subjectType", `x.${c("subjectType")}`),
      filterAny("subjectId", `x.${c("subjectId")}`),
      filterAny("status", `x.${c("status")}::text`),
      ...(has("documentType")
        ? [filterAny("documentTypeId", `x.${c("documentType")}`, "uuid")]
        : []),
      `(v_search is null or x.${c("name")} ilike v_search)`,
    ],
    keys: newestKeys,
    sorts: {
      createdAt: newestKeys,
      name: [
        { expr: `lower(x.${c("name")})`, dir: "asc", type: "text" },
        attachmentIdKey,
      ],
      size: [
        { expr: `coalesce(x.${c("size")}, 0)`, dir: "desc", type: "bigint" },
        attachmentIdKey,
      ],
    },
    facets: {
      status: `x.${c("status")}::text`,
      subjectType: `x.${c("subjectType")}`,
    },
    rowJson:
      authors === undefined
        ? withExtraFields(rowJson("x"), "x", extras)
        : authors.attach(
            withExtraFields(rowJson("x"), "x", extras),
            authors.call(`array[x.${c("id")}]`),
            "x",
          ),
    defaultLimit: 50,
    maxLimit: 200,
    invalid: (message: string) => fail("ATTACHMENT_INVALID", message, "22023"),
  } as const;

  const pageRead = ctx.read(
    filterFirst("subjectType", "v_filters"),
    filterFirst("subjectId", "v_filters"),
    "page_attachments",
  );

  return `
-- A keyset page of files, newest first (ADR 1077). Row security decides what
-- the caller sees. filters is { subjectType, subjectId, status${has("documentType") ? ", documentTypeId" : ""} (each a value
-- or a list), search, sort (createdAt, name, size), direction, facet, count,
-- limit, after, offset, paged, total, totalCap }.
create or replace function ${fn("page_attachments")}(tenant ${id}, filters jsonb default '{}')
returns jsonb
language plpgsql
${ctx.readVolatility()}
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_attachments.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  ${listDeclare(attachmentPage)}
begin${
    pageRead === ""
      ? ""
      : `
  if v_facet is null and not v_count and ${filterFirst("subjectType")} is not null and ${filterFirst("subjectId")} is not null then
    ${pageRead}
  end if;`
  }
  ${listBody(attachmentPage)}
end;
$$;

revoke execute on function ${fn("page_attachments")}(${id}, jsonb) from public, anon;
grant execute on function ${fn("page_attachments")}(${id}, jsonb) to authenticated, service_role;

`;
}
