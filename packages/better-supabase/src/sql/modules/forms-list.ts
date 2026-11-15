import type { BlockSqlContext } from "../context.ts";

import {
  filterAny,
  filterFlag,
  listBody,
  listDeclare,
  searchPattern,
} from "../list-template.ts";
import { fail, SERVICE_CALLER, userGrant } from "../shared.ts";
import { OPERATIONS } from "./permissions-model.ts";

/**
 * `list_forms`: one page of an organization's forms (ADR 0749). `formJson`
 * renders one row over the alias it is given.
 */
export function formListFunction(
  ctx: BlockSqlContext,
  formJson: (row: string) => string,
): string {
  const forms = ctx.table("forms");
  const fn = (name: string): string => ctx.fn(name);
  const f = (column: string): string => ctx.col("forms", column);
  const read = ctx.permission("read", OPERATIONS["forms.read"]);

  const list = {
    name: "list_forms",
    from: forms,
    alias: "x",
    where: [
      `x.${f("tenant")} = list_forms.tenant`,
      filterAny("status", `x.${f("status")}::text`),
      `(v_search is null or x.${f("title")} ilike v_search or x.${f("key")} ilike v_search)`,
    ],
    keys: [
      { expr: `x.${f("createdAt")}`, dir: "desc", type: "timestamptz" },
      { expr: `x.${f("id")}`, dir: "desc", type: "uuid" },
    ],
    sorts: {
      createdAt: [
        { expr: `x.${f("createdAt")}`, dir: "desc", type: "timestamptz" },
        { expr: `x.${f("id")}`, dir: "desc", type: "uuid" },
      ],
      title: [
        { expr: `x.${f("title")}`, dir: "asc", type: "text" },
        { expr: `x.${f("id")}`, dir: "asc", type: "uuid" },
      ],
      key: [
        { expr: `x.${f("key")}`, dir: "asc", type: "text" },
        { expr: `x.${f("id")}`, dir: "asc", type: "uuid" },
      ],
    },
    facets: { status: `x.${f("status")}` },
    rowJson: formJson("x"),
    defaultLimit: 200,
    maxLimit: 500,
    invalid: (message: string): string =>
      fail("FORM_INVALID", message, "22023"),
  } as const;

  return `-- Newest first. filters is { status (a value or a list), search, sort, direction,
-- facet, count, limit, after, offset, paged, total, totalCap } (ADR 0749).
create or replace function ${fn("list_forms")}(tenant ${ctx.idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_forms.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  ${listDeclare(list)}
begin
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", "list_forms.tenant", read)}) then
    ${fail("FORM_FORBIDDEN", "not allowed to read forms")}
  end if;
  ${listBody(list)}
end;
$$;
${userGrant(`${fn("list_forms")}(${ctx.idType}, jsonb)`)}`;
}

/**
 * `page_form_submissions`: one keyset page of an organization's submissions
 * (ADR 1077). Reviewers see every submission and everyone else their own.
 */
export function formSubmissionPageFunction(
  ctx: BlockSqlContext,
  submissionJson: (row: string) => string,
): string {
  const submissions = ctx.table("submissions");
  const fn = (name: string): string => ctx.fn(name);
  const s = (column: string): string => ctx.col("submissions", column);
  const review = ctx.permission("review", OPERATIONS["forms.review"]);
  const archivable = ctx.has("submissions", "archivedAt");

  const idKey = { expr: `x.${s("id")}`, dir: "desc", type: "uuid" } as const;

  const newestKeys = [
    { expr: `x.${s("createdAt")}`, dir: "desc", type: "timestamptz" },
    idKey,
  ] as const;

  const list = {
    name: "page_form_submissions",
    from: submissions,
    alias: "x",
    where: [
      `x.${s("tenant")} = page_form_submissions.tenant`,
      filterAny("formId", `x.${s("form")}`, "uuid"),
      filterAny("status", `x.${s("status")}::text`),
      filterAny("respondentId", `x.${s("respondent")}`, "uuid"),
      ...(archivable
        ? [`(${filterFlag("includeArchived")} or x.${s("archivedAt")} is null)`]
        : []),
      `(v_search is null or x.${s("answers")}::text ilike v_search)`,
      `(v_all or x.${s("respondent")} = auth.uid())`,
    ],
    keys: newestKeys,
    sorts: {
      createdAt: newestKeys,
      submittedAt: [
        {
          expr: `coalesce(x.${s("submittedAt")}, timestamptz '-infinity')`,
          dir: "desc",
          type: "timestamptz",
        },
        idKey,
      ],
    },
    facets: { status: `x.${s("status")}`, formId: `x.${s("form")}::text` },
    rowJson: submissionJson("x"),
    defaultLimit: 50,
    maxLimit: 200,
    invalid: (message: string): string =>
      fail("FORM_INVALID", message, "22023"),
  } as const;

  return `-- Newest first. Reviewers see every submission; others see their own.
-- filters is { formId, status, respondentId (each a value or a list)${archivable ? ", includeArchived" : ""}, search
-- (a text match in the answers), sort (createdAt, submittedAt), direction,
-- facet, count, limit, after, offset, paged, total, totalCap } (ADR 1077).
create or replace function ${fn("page_form_submissions")}(tenant ${ctx.idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_form_submissions.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  v_all boolean := ${SERVICE_CALLER} or ${ctx.can("tenant", "page_form_submissions.tenant", review)};
  ${listDeclare(list)}
begin
  ${listBody(list)}
end;
$$;
${userGrant(`${fn("page_form_submissions")}(${ctx.idType}, jsonb)`)}`;
}
