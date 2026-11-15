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
import { asText } from "./over-app.ts";

/** What the knowledge module's `build` hands the document page function. */
export interface KnowledgeDocumentPageDeps {
  readonly id: string;
  /** The quoted document columns. */
  readonly d: {
    readonly id: string;
    readonly tenant: string;
    readonly collection: string;
    readonly scope: string;
    readonly scopeId: string;
    readonly status: string;
    readonly subjectType: string;
    readonly subjectId: string;
    readonly title: string;
  };
  readonly collected: boolean;
  readonly subjectColumns: boolean;
  readonly createdAt: (row: string) => string;
  readonly documentJson: (row: string) => string;
}

/** `page_knowledge_documents`: the documents as a keyset page (ADR 1077). */
export function knowledgeDocumentPage(
  ctx: BlockSqlContext,
  deps: KnowledgeDocumentPageDeps,
): string {
  const { d, collected, subjectColumns, createdAt, documentJson } = deps;
  const fn = (name: string): string => ctx.fn(name);

  const documentIdKey = {
    expr: `x.${d.id}`,
    dir: "asc",
    type: "uuid",
  } as const;

  const documentPage = {
    name: "page_knowledge_documents",
    from: ctx.table("documents"),
    alias: "x",
    where: [
      collected
        ? `(x.${d.tenant} = page_knowledge_documents.tenant or (x.${d.tenant} is null and v_collection is not null))
        and (v_collection is null or x.${d.collection} = v_collection::uuid)`
        : `x.${d.tenant} = page_knowledge_documents.tenant
        and v_collection is null`,
      filterAny("scope", asText(ctx, "documents", `x.${d.scope}`)),
      `(v_scope_id is null or x.${d.scopeId} = v_scope_id::uuid)`,
      filterAny("status", `x.${d.status}::text`),
      subjectColumns
        ? `(v_subject_type is null or x.${d.subjectType} = v_subject_type)
        and (v_subject_id is null or x.${d.subjectId} = v_subject_id)`
        : "(v_subject_type is null and v_subject_id is null)",
      `(v_search is null or x.${d.title} ilike v_search)`,
    ],
    keys: [
      { expr: createdAt("x"), dir: "desc", type: "timestamptz" },
      documentIdKey,
    ],
    sorts: {
      createdAt: [
        { expr: createdAt("x"), dir: "desc", type: "timestamptz" },
        documentIdKey,
      ],
      title: [
        { expr: `lower(x.${d.title})`, dir: "asc", type: "text" },
        documentIdKey,
      ],
    },
    facets: {
      scope: asText(ctx, "documents", `x.${d.scope}`),
      status: `x.${d.status}`,
    },
    rowJson: documentJson("x"),
    defaultLimit: 50,
    maxLimit: 200,
    invalid: (message: string) =>
      fail("KNOWLEDGE_DOCUMENT_INVALID", message, "22023"),
  } as const;

  return `-- The documents the caller can read in a tenant as a keyset page (ADR 1077).
-- filters is { collectionId (one uuid), scopeId (one uuid), subjectType, subjectId,
-- scope (a value or a list), status (a value or a list), search (title), sort
-- (createdAt, title), direction, facet, count, limit, after, offset, paged,
-- total, totalCap }. With a collection, its documents, system ones included.
create or replace function ${fn("page_knowledge_documents")}(tenant ${deps.id}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_knowledge_documents.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  v_collection text := ${filterFirst("collectionId")};
  v_scope_id text := ${filterFirst("scopeId")};
  v_subject_type text := ${filterFirst("subjectType")};
  v_subject_id text := ${filterFirst("subjectId")};
  ${listDeclare(documentPage)}
begin
  if ${filterHasInvalid("collectionId")} or ${filterHasInvalid("scopeId")} then
    ${fail("KNOWLEDGE_DOCUMENT_INVALID", "collectionId and scopeId are uuids", "22023")}
  end if;
  ${listBody(documentPage)}
end;
$$;
${userGrant(`${fn("page_knowledge_documents")}(${deps.id}, jsonb)`)}`;
}
