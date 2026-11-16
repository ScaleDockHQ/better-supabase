import type { AdvisoriesSql } from "./advisories-sql.ts";

import {
  filterAny,
  filterFlag,
  listBody,
  listDeclare,
  searchPattern,
} from "../list-template.ts";
import { fail, userGrant } from "../shared.ts";

/**
 * The keyset page functions of the advisories block (ADR 1077). Both gate on
 * the `advisories.read` permission like `list_advisories` and run as definer,
 * because the tables have no read policy of their own.
 */
export function advisoryPageFunctions(q: AdvisoriesSql): string {
  const {
    fn,
    a,
    x,
    advisories,
    vulnerabilities,
    advisoryJson,
    vulnerabilityJson,
    ctx,
  } = q;

  const idType = ctx.idType;

  const advisoryId = {
    expr: `y.${a("id")}`,
    dir: "desc",
    type: "uuid",
  } as const;

  const advisoryCreated = [
    { expr: `y.${a("createdAt")}`, dir: "desc", type: "timestamptz" },
    advisoryId,
  ] as const;

  const advisoryPage = {
    name: "page_advisories",
    from: advisories,
    alias: "y",
    where: [
      `y.${a("tenant")} = page_advisories.tenant`,
      filterAny("status", `y.${a("status")}::text`),
      filterAny("severity", `y.${a("severity")}::text`),
      filterAny("productId", `y.${a("product")}`, "uuid"),
      `(v_search is null or y.${a("title")} ilike v_search or y.${a("trackingId")} ilike v_search or y.${a("summary")} ilike v_search)`,
    ],
    keys: advisoryCreated,
    sorts: {
      createdAt: advisoryCreated,
      trackingId: [
        { expr: `y.${a("trackingId")}`, dir: "asc", type: "text" },
        advisoryId,
      ],
      title: [
        { expr: `lower(y.${a("title")})`, dir: "asc", type: "text" },
        advisoryId,
      ],
    },
    facets: {
      status: `y.${a("status")}::text`,
      severity: `coalesce(y.${a("severity")}::text, 'none')`,
    },
    rowJson: advisoryJson("y"),
    defaultLimit: 50,
    maxLimit: 200,
    invalid: (message: string) => fail("ADVISORY_INVALID", message, "22023"),
  } as const;

  const vulnId = { expr: `y.${x("id")}`, dir: "asc", type: "uuid" } as const;

  const vulnByName = [
    { expr: `y.${x("vulnId")}`, dir: "asc", type: "text" },
    vulnId,
  ] as const;

  const vulnerabilityPage = {
    name: "page_vulnerabilities",
    from: vulnerabilities,
    alias: "y",
    where: [
      `y.${x("tenant")} = page_vulnerabilities.tenant`,
      filterAny("severity", `coalesce(y.${x("severity")}::text, 'none')`),
      `(not ${filterFlag("kev")} or y.${x("kev")})`,
      `(v_search is null or y.${x("vulnId")} ilike v_search or y.${x("summary")} ilike v_search)`,
    ],
    keys: vulnByName,
    sorts: {
      vulnId: vulnByName,
      cvssScore: [
        {
          expr: `coalesce(y.${x("cvssScore")}, -1)`,
          dir: "desc",
          type: "numeric",
        },
        vulnId,
      ],
      epssScore: [
        {
          expr: `coalesce(y.${x("epssScore")}, -1)`,
          dir: "desc",
          type: "numeric",
        },
        vulnId,
      ],
    },
    facets: { severity: `coalesce(y.${x("severity")}::text, 'none')` },
    rowJson: vulnerabilityJson("y"),
    defaultLimit: 50,
    maxLimit: 200,
    invalid: (message: string) => fail("ADVISORY_INVALID", message, "22023"),
  } as const;

  const page = (
    name: string,
    spec: typeof advisoryPage | typeof vulnerabilityPage,
    doc: string,
  ): string => `
-- ${doc}
create or replace function ${fn(name)}(tenant ${idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(${name}.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  ${listDeclare(spec)}
begin
  if not ${q.allowed(`${name}.tenant`, q.read)} then
    ${q.forbidden("not allowed to read advisories")}
  end if;
  ${listBody(spec)}
end;
$$;
${userGrant(`${fn(name)}(${idType}, jsonb)`)}
`;

  return `${page(
    "page_advisories",
    advisoryPage,
    "The organization's advisories as a keyset page, newest first (ADR 1077). filters is { status, severity, productId (each a value or a list), search (title, tracking id, summary), sort (createdAt, trackingId, title), direction, facet, count, limit, after, offset, paged, total, totalCap }.",
  )}${page(
    "page_vulnerabilities",
    vulnerabilityPage,
    "The tracked vulnerabilities as a keyset page, by id (ADR 1077). filters is { severity (a value or a list), kev (true keeps exploited ones), search (id, summary), sort (vulnId, cvssScore, epssScore), direction, facet, count, limit, after, offset, paged, total, totalCap }.",
  )}`;
}
