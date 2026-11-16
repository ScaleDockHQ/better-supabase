import type { BlockSqlContext } from "../context.ts";

import {
  filterAny,
  filterHasInvalid,
  listBody,
  listDeclare,
  searchPattern,
} from "../list-template.ts";
import { fail, serviceGrant } from "../shared.ts";

/** What the ai-guardrails module's `build` hands the page functions. */
export interface GuardrailPageDeps {
  readonly policyJson: (row: string) => string;
  readonly decisionJson: (row: string) => string;
}

/**
 * `page_guardrail_policies`, `page_guardrail_decisions` and
 * `get_guardrail_policy_by_id`: the keyset pages and the read by id of the
 * block list contract (ADR 1077). Only the service role calls them, as it does
 * `list_guardrail_policies`.
 */
export function guardrailPagesSql(
  ctx: BlockSqlContext,
  deps: GuardrailPageDeps,
): string {
  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);

  const p = (column: string): string => ctx.col("policies", column);

  const d = (column: string): string => ctx.col("decisions", column);

  const policies = ctx.table("policies");
  const decisions = ctx.table("decisions");

  const invalid = (message: string): string =>
    fail("GUARDRAIL_INVALID", message, "22023");

  const policyIdKey = {
    expr: `x.${p("id")}`,
    dir: "asc",
    type: "uuid",
  } as const;

  const decisionIdKey = {
    expr: `x.${d("id")}`,
    dir: "desc",
    type: "uuid",
  } as const;

  const byAgent = [
    { expr: `x.${p("agent")}`, dir: "asc", type: "text" },
    { expr: `x.${p("stage")}`, dir: "asc", type: "text" },
    policyIdKey,
  ] as const;

  const policyPage = {
    name: "page_guardrail_policies",
    from: policies,
    alias: "x",
    where: [
      `coalesce(x.${p("tenant")}::text, '') = coalesce(page_guardrail_policies.tenant::text, '')`,
      filterAny("agent", `x.${p("agent")}`),
      filterAny("stage", `x.${p("stage")}`),
      filterAny("enabled", `x.${p("enabled")}::text`),
      `(v_search is null or x.${p("agent")} ilike v_search)`,
    ],
    keys: byAgent,
    sorts: {
      agent: byAgent,
      updatedAt: [
        { expr: `x.${p("updatedAt")}`, dir: "desc", type: "timestamptz" },
        policyIdKey,
      ],
    },
    facets: { stage: `x.${p("stage")}`, enabled: `x.${p("enabled")}` },
    rowJson: deps.policyJson("x"),
    defaultLimit: 50,
    maxLimit: 200,
    invalid,
  } as const;

  const newest = [
    { expr: `x.${d("createdAt")}`, dir: "desc", type: "timestamptz" },
    decisionIdKey,
  ] as const;

  const decisionPage = {
    name: "page_guardrail_decisions",
    from: decisions,
    alias: "x",
    where: [
      `(page_guardrail_decisions.tenant is null or x.${d("tenant")} = page_guardrail_decisions.tenant)`,
      filterAny("agent", `x.${d("agent")}`),
      filterAny("decision", `x.${d("decision")}`),
      filterAny("stage", `x.${d("stage")}`),
      `(v_search is null or x.${d("agent")} ilike v_search)`,
    ],
    keys: newest,
    sorts: {
      createdAt: newest,
      agent: [
        { expr: `x.${d("agent")}`, dir: "asc", type: "text" },
        { expr: `x.${d("id")}`, dir: "asc", type: "uuid" },
      ],
    },
    facets: { decision: `x.${d("decision")}`, stage: `x.${d("stage")}` },
    rowJson: deps.decisionJson("x"),
    defaultLimit: 50,
    maxLimit: 200,
    invalid,
  } as const;

  const page = (
    name: string,
    comment: string,
    options: typeof policyPage | typeof decisionPage,
    checks: string,
  ): string => `${comment}
create or replace function ${fn(name)}(tenant ${id} default null, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(${name}.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  ${listDeclare(options)}
begin
  ${checks}
  ${listBody(options)}
end;
$$;
${serviceGrant(`${fn(name)}(${id}, jsonb)`)}`;

  const stageCheck = (key: string, allowed: readonly string[]): string =>
    `if ${filterHasInvalid(key, allowed)} then
    ${invalid(`${key} is one of ${allowed.join(", ")}`)}
  end if;`;

  return `${page(
    "page_guardrail_policies",
    `-- The policies a tenant has saved (the system's when tenant is null) as a
-- keyset page (ADR 1077), by agent and stage. filters is { agent, stage,
-- enabled (a value or a list), search (agent), sort (agent, updatedAt),
-- direction, facet, count, limit, after, offset, paged, total, totalCap }.`,
    policyPage,
    stageCheck("stage", ["input", "output"]),
  )}

${page(
  "page_guardrail_decisions",
  `-- The decision log as a keyset page (ADR 1077), newest first. A tenant reads
-- its own decisions; null reads every tenant's. filters is { agent, decision,
-- stage (a value or a list), search (agent), sort (createdAt, agent),
-- direction, facet, count, limit, after, offset, paged, total, totalCap }.`,
  decisionPage,
  `${stageCheck("stage", ["input", "output"])}
  ${stageCheck("decision", ["allow", "redact", "block"])}`,
)}

-- One saved policy by id, or null.
create or replace function ${fn("get_guardrail_policy_by_id")}(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${deps.policyJson("x")} from ${policies} x where x.${p("id")} = get_guardrail_policy_by_id.id
$$;
${serviceGrant(`${fn("get_guardrail_policy_by_id")}(uuid)`)}`;
}
