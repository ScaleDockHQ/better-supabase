import type { RisksEvents } from "../../blocks/risks/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  addExtraColumns,
  fail,
  lockTable,
  schemaPreamble,
  userGrant,
} from "../shared.ts";
import { moduleOperations } from "./permissions-model.ts";

const EVENTS: BlockSqlEvents<RisksEvents> = {
  "risk_matrix.created": {
    subject: "risk-matrices",
    payload: ["organizationId", "matrixId", "key"],
  },
  "risk_matrix.updated": {
    subject: "risk-matrices",
    payload: ["organizationId", "matrixId", "key"],
  },
  "risk.created": {
    subject: "risks",
    payload: ["organizationId", "riskId", "number"],
  },
  "risk.updated": {
    subject: "risks",
    payload: ["organizationId", "riskId", "number", "changed"],
  },
  "risk.assessed": {
    subject: "risks",
    payload: ["organizationId", "riskId", "number", "inherentBand", "residualBand"],
  },
  "risk.treatment_changed": {
    subject: "risks",
    payload: ["organizationId", "riskId", "number", "treatment"],
  },
  "risk.reviewed": {
    subject: "risks",
    payload: ["organizationId", "riskId", "number"],
  },
  "risk.closed": {
    subject: "risks",
    payload: ["organizationId", "riskId", "number"],
  },
  "risk.review_reminded": {
    subject: "risks",
    payload: ["organizationId", "riskId", "number", "nextReviewOn"],
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    risk: {
      table: "risks",
      singular: "risk",
      primary: true,
      subject: {
        title: "title",
        permissions: { read: "read", write: "write" },
        search: { title: "title", body: ["number", "description", "cause", "consequence"] },
        deletedAt: "archivedAt",
      },
    },
    risk_matrix: { table: "matrices", singular: "risk_matrix" },
    risk_assessment: { table: "assessments", singular: "risk_assessment" },
  },
  events: EVENTS,
  hooks: [],
  options: ["categories", "extraColumns"],
  tables: {
    matrices: {
      name: "risk_matrices",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        key: "key",
        name: "name",
        likelihoodLevels: "likelihood_levels",
        impactLevels: "impact_levels",
        bands: "bands",
        scoring: "scoring",
        isDefault: "is_default",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["createdAt", "updatedAt"],
    },
    risks: {
      name: "risks",
      app: {},
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        matrix: "matrix_id",
        number: "number",
        title: "title",
        description: "description",
        category: "category",
        cause: "cause",
        consequence: "consequence",
        owner: "owner_id",
        status: "status",
        treatment: "treatment",
        reviewIntervalMonths: "review_interval_months",
        nextReviewOn: "next_review_on",
        inherentLikelihood: "inherent_likelihood",
        inherentImpact: "inherent_impact",
        inherentScore: "inherent_score",
        inherentBand: "inherent_band",
        residualLikelihood: "residual_likelihood",
        residualImpact: "residual_impact",
        residualScore: "residual_score",
        residualBand: "residual_band",
        currentAssessment: "current_assessment_id",
        archivedAt: "archived_at",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: [
        "description",
        "cause",
        "consequence",
        "owner",
        "treatment",
        "reviewIntervalMonths",
        "nextReviewOn",
        "inherentLikelihood",
        "inherentImpact",
        "inherentScore",
        "inherentBand",
        "residualLikelihood",
        "residualImpact",
        "residualScore",
        "residualBand",
        "currentAssessment",
        "archivedAt",
        "createdBy",
        "createdAt",
        "updatedAt",
      ],
    },
    assessments: {
      name: "risk_assessments",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        risk: "risk_id",
        inherentLikelihood: "inherent_likelihood",
        inherentImpact: "inherent_impact",
        inherentScore: "inherent_score",
        inherentBand: "inherent_band",
        residualLikelihood: "residual_likelihood",
        residualImpact: "residual_impact",
        residualScore: "residual_score",
        residualBand: "residual_band",
        rationale: "rationale",
        assessedBy: "assessed_by",
        assessedAt: "assessed_at",
      },
      optional: ["rationale", "assessedBy", "assessedAt"],
    },
  },
};

function tables(ctx: BlockSqlContext): string {
  const matrices = ctx.table("matrices");
  const risks = ctx.table("risks");
  const assessments = ctx.table("assessments");
  const m = (column: string): string => ctx.col("matrices", column);
  const r = (column: string): string => ctx.col("risks", column);
  const a = (column: string): string => ctx.col("assessments", column);
  const permissions = moduleOperations("risks");
  const read = ctx.permission("read", permissions.read);

  const extras = ctx.extraColumns("risks", [
    "id",
    "tenant",
    "matrix",
    "number",
    "title",
    "description",
    "category",
    "cause",
    "consequence",
    "owner",
    "status",
    "treatment",
    "reviewIntervalMonths",
    "nextReviewOn",
    "inherentLikelihood",
    "inherentImpact",
    "inherentScore",
    "inherentBand",
    "residualLikelihood",
    "residualImpact",
    "residualScore",
    "residualBand",
    "currentAssessment",
    "archivedAt",
    "createdBy",
    "createdAt",
    "updatedAt",
  ]);

  return `
create table if not exists ${matrices} (
  ${m("id")} uuid primary key default gen_random_uuid(),
  ${m("tenant")} ${ctx.idType} not null,
  ${m("key")} text not null check (${m("key")} ~ '^[a-z][a-z0-9_]{0,40}$'),
  ${m("name")} text not null,
  ${m("likelihoodLevels")} jsonb not null,
  ${m("impactLevels")} jsonb not null,
  ${m("bands")} jsonb not null,
  ${m("scoring")} text not null default 'product' check (${m("scoring")} in ('product', 'sum')),
  ${m("isDefault")} boolean not null default false,
  ${m("createdAt")} timestamptz not null default now(),
  ${m("updatedAt")} timestamptz not null default now(),
  unique (${m("tenant")}, ${m("key")})
);
create unique index if not exists ${ctx.tableName("matrices").name}_default_idx on ${matrices} (${m("tenant")}) where ${m("isDefault")};
${lockTable(matrices, { read: true })}
${renderPolicy(makePolicy({ table: matrices, name: `${ctx.tableName("matrices").name}_read`, command: "select", roles: ["authenticated"], using: ctx.scope.check(m("tenant"), read) }))}

create table if not exists ${risks} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${ctx.idType} not null,
  ${r("matrix")} uuid not null,
  ${r("number")} text not null,
  ${r("title")} text not null check (length(${r("title")}) between 1 and 200),
  ${r("description")} text,
  ${r("category")} text,
  ${r("cause")} text,
  ${r("consequence")} text,
  ${r("owner")} uuid,
  ${r("status")} text not null default 'identified' check (${r("status")} in ('identified', 'assessed', 'treating', 'accepted', 'closed')),
  ${r("treatment")} text check (${r("treatment")} in ('mitigate', 'accept', 'transfer', 'avoid')),
  ${r("reviewIntervalMonths")} integer check (${r("reviewIntervalMonths")} between 1 and 120),
  ${r("nextReviewOn")} date,
  ${r("inherentLikelihood")} integer,
  ${r("inherentImpact")} integer,
  ${r("inherentScore")} integer,
  ${r("inherentBand")} text,
  ${r("residualLikelihood")} integer,
  ${r("residualImpact")} integer,
  ${r("residualScore")} integer,
  ${r("residualBand")} text,
  ${r("currentAssessment")} uuid,
  ${r("archivedAt")} timestamptz,
  ${r("createdBy")} uuid default auth.uid(),
  ${r("createdAt")} timestamptz not null default now(),
  ${r("updatedAt")} timestamptz not null default now(),
  unique (${r("tenant")}, ${r("number")}),
  foreign key (${r("tenant")}, ${r("matrix")}) references ${matrices} (${m("tenant")}, ${m("id")})
);${addExtraColumns(risks, extras)}
create index if not exists ${ctx.tableName("risks").name}_status_idx on ${risks} (${r("tenant")}, ${r("status")});
create index if not exists ${ctx.tableName("risks").name}_review_idx on ${risks} (${r("tenant")}, ${r("nextReviewOn")});
${lockTable(risks, { read: true })}
${renderPolicy(makePolicy({ table: risks, name: `${ctx.tableName("risks").name}_read`, command: "select", roles: ["authenticated"], using: ctx.scope.check(r("tenant"), read) }))}

create table if not exists ${assessments} (
  ${a("id")} uuid primary key default gen_random_uuid(),
  ${a("tenant")} ${ctx.idType} not null,
  ${a("risk")} uuid not null,
  ${a("inherentLikelihood")} integer not null,
  ${a("inherentImpact")} integer not null,
  ${a("inherentScore")} integer not null,
  ${a("inherentBand")} text not null,
  ${a("residualLikelihood")} integer not null,
  ${a("residualImpact")} integer not null,
  ${a("residualScore")} integer not null,
  ${a("residualBand")} text not null,
  ${a("rationale")} text,
  ${a("assessedBy")} uuid default auth.uid(),
  ${a("assessedAt")} timestamptz not null default now(),
  foreign key (${a("risk")}) references ${risks} (${r("id")}) on delete cascade
);
create index if not exists ${ctx.tableName("assessments").name}_parent_idx on ${assessments} (${a("risk")});
${lockTable(assessments, { read: true })}
${renderPolicy(makePolicy({ table: assessments, name: `${ctx.tableName("assessments").name}_read`, command: "select", roles: ["authenticated"], using: ctx.scope.check(a("tenant"), read) }))}
`;
}

function functions(ctx: BlockSqlContext): string {
  const matrices = ctx.table("matrices");
  const risks = ctx.table("risks");
  const assessments = ctx.table("assessments");
  const m = (column: string): string => ctx.col("matrices", column);
  const r = (column: string): string => ctx.col("risks", column);
  const a = (column: string): string => ctx.col("assessments", column);
  const fn = (name: string): string => ctx.fn(name);
  const permissions = moduleOperations("risks");
  const read = ctx.permission("read", permissions.read);
  const write = ctx.permission("write", permissions.write);
  const assess = ctx.permission("assess", permissions.assess);
  const manage = ctx.permission("manage", permissions.manage);

  const allowed = (tenant: string, permission: string): string =>
    `(select auth.uid()) is not null and ${ctx.can("tenant", tenant, permission)}`;

  const matrixJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${m("id")}, 'organizationId', ${row}.${m("tenant")}, 'key', ${row}.${m("key")}, 'name', ${row}.${m("name")}, 'likelihoodLevels', ${row}.${m("likelihoodLevels")}, 'impactLevels', ${row}.${m("impactLevels")}, 'bands', ${row}.${m("bands")}, 'scoring', ${row}.${m("scoring")}, 'isDefault', ${row}.${m("isDefault")})`;

  const riskJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${r("id")}, 'organizationId', ${row}.${r("tenant")}, 'matrixId', ${row}.${r("matrix")}, 'number', ${row}.${r("number")}, 'title', ${row}.${r("title")}, 'description', ${row}.${r("description")}, 'category', ${row}.${r("category")}, 'cause', ${row}.${r("cause")}, 'consequence', ${row}.${r("consequence")}, 'ownerId', ${row}.${r("owner")}, 'status', ${row}.${r("status")}, 'treatment', ${row}.${r("treatment")}, 'reviewIntervalMonths', ${row}.${r("reviewIntervalMonths")}, 'nextReviewOn', ${row}.${r("nextReviewOn")}, 'inherentLikelihood', ${row}.${r("inherentLikelihood")}, 'inherentImpact', ${row}.${r("inherentImpact")}, 'inherentScore', ${row}.${r("inherentScore")}, 'inherentBand', ${row}.${r("inherentBand")}, 'residualLikelihood', ${row}.${r("residualLikelihood")}, 'residualImpact', ${row}.${r("residualImpact")}, 'residualScore', ${row}.${r("residualScore")}, 'residualBand', ${row}.${r("residualBand")}, 'currentAssessmentId', ${row}.${r("currentAssessment")}, 'createdAt', ${row}.${r("createdAt")}, 'updatedAt', ${row}.${r("updatedAt")})`;

  const band = (score: string, levels: string): string =>
    `(select b ->> 'key' from jsonb_array_elements(${levels}) b where (b ->> 'min')::integer <= ${score} and (b ->> 'max')::integer >= ${score} limit 1)`;

  return `
create or replace function ${fn("ensure_risk_matrix")}(tenant ${ctx.idType})
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  select x.${m("id")} into v_id from ${matrices} x where x.${m("tenant")} = ensure_risk_matrix.tenant and x.${m("isDefault")} limit 1;
  if v_id is not null then
    return v_id;
  end if;
  insert into ${matrices} (${m("tenant")}, ${m("key")}, ${m("name")}, ${m("likelihoodLevels")}, ${m("impactLevels")}, ${m("bands")}, ${m("scoring")}, ${m("isDefault")})
  values (ensure_risk_matrix.tenant, 'default', 'Default', '[{"value":1,"label":"Rare"},{"value":2,"label":"Unlikely"},{"value":3,"label":"Possible"},{"value":4,"label":"Likely"},{"value":5,"label":"Almost certain"}]'::jsonb, '[{"value":1,"label":"Negligible"},{"value":2,"label":"Minor"},{"value":3,"label":"Moderate"},{"value":4,"label":"Major"},{"value":5,"label":"Severe"}]'::jsonb, '[{"key":"low","label":"Low","min":1,"max":4},{"key":"medium","label":"Medium","min":5,"max":9},{"key":"high","label":"High","min":10,"max":16},{"key":"critical","label":"Critical","min":17,"max":25}]'::jsonb, 'product', true)
  returning ${m("id")} into v_id;
  return v_id;
end;
$$;
${userGrant(`${fn("ensure_risk_matrix")}(${ctx.idType})`)}

create or replace function ${fn("save_risk_matrix")}(tenant ${ctx.idType}, key text, name text, likelihood_levels jsonb, impact_levels jsonb, bands jsonb, scoring text default 'product', is_default boolean default false, matrix_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${matrices}%rowtype;
  v_created boolean := false;
begin
  if not ${allowed("save_risk_matrix.tenant", manage)} then
    ${fail("RISK_FORBIDDEN", "not allowed to manage risk matrices")}
  end if;
  if save_risk_matrix.key !~ '^[a-z][a-z0-9_]{0,40}$' or jsonb_typeof(save_risk_matrix.likelihood_levels) <> 'array' or jsonb_typeof(save_risk_matrix.impact_levels) <> 'array' or jsonb_typeof(save_risk_matrix.bands) <> 'array' then
    ${fail("RISK_MATRIX_INVALID", "the matrix shape is invalid", "22023")}
  end if;
  if save_risk_matrix.matrix_id is null then
    insert into ${matrices} (${m("tenant")}, ${m("key")}, ${m("name")}, ${m("likelihoodLevels")}, ${m("impactLevels")}, ${m("bands")}, ${m("scoring")}, ${m("isDefault")})
    values (save_risk_matrix.tenant, save_risk_matrix.key, trim(save_risk_matrix.name), save_risk_matrix.likelihood_levels, save_risk_matrix.impact_levels, save_risk_matrix.bands, coalesce(save_risk_matrix.scoring, 'product'), coalesce(save_risk_matrix.is_default, false))
    on conflict (${m("tenant")}, ${m("key")}) do update
      set ${m("name")} = excluded.${m("name")}, ${m("likelihoodLevels")} = excluded.${m("likelihoodLevels")}, ${m("impactLevels")} = excluded.${m("impactLevels")}, ${m("bands")} = excluded.${m("bands")}, ${m("scoring")} = excluded.${m("scoring")}, ${m("isDefault")} = excluded.${m("isDefault")}, ${m("updatedAt")} = now()
    returning * into v_row;
    v_created := true;
  else
    update ${matrices} x set ${m("key")} = save_risk_matrix.key, ${m("name")} = trim(save_risk_matrix.name), ${m("likelihoodLevels")} = save_risk_matrix.likelihood_levels, ${m("impactLevels")} = save_risk_matrix.impact_levels, ${m("bands")} = save_risk_matrix.bands, ${m("scoring")} = coalesce(save_risk_matrix.scoring, 'product'), ${m("isDefault")} = coalesce(save_risk_matrix.is_default, false), ${m("updatedAt")} = now()
      where x.${m("id")} = save_risk_matrix.matrix_id and x.${m("tenant")} = save_risk_matrix.tenant
      returning * into v_row;
    if not found then
      ${fail("RISK_MATRIX_NOT_FOUND", "risk matrix not found", "P0002")}
    end if;
  end if;
  if v_created then
    ${ctx.record({
      type: "risk_matrix.created",
      payload: `jsonb_build_object('organizationId', v_row.${m("tenant")}, 'matrixId', v_row.${m("id")}, 'key', v_row.${m("key")})`,
      subject: `'risk-matrices/' || v_row.${m("id")}::text`,
      tenant: `v_row.${m("tenant")}`,
      audit: {
        category: "data",
        targetType: "risk_matrix",
        recordId: `v_row.${m("id")}::text`,
        summary: "'saved risk matrix'",
      },
    })}
  else
    ${ctx.record({
      type: "risk_matrix.updated",
      payload: `jsonb_build_object('organizationId', v_row.${m("tenant")}, 'matrixId', v_row.${m("id")}, 'key', v_row.${m("key")})`,
      subject: `'risk-matrices/' || v_row.${m("id")}::text`,
      tenant: `v_row.${m("tenant")}`,
      audit: {
        category: "data",
        targetType: "risk_matrix",
        recordId: `v_row.${m("id")}::text`,
        summary: "'saved risk matrix'",
      },
    })}
  end if;
  return ${matrixJson("v_row")};
end;
$$;
${userGrant(`${fn("save_risk_matrix")}(${ctx.idType}, text, text, jsonb, jsonb, jsonb, text, boolean, uuid)`)}

create or replace function ${fn("list_risk_matrices")}(tenant ${ctx.idType})
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(${matrixJson("x")} order by x.${m("isDefault")} desc, x.${m("key")}), '[]'::jsonb)
  from ${matrices} x
  where x.${m("tenant")} = $1 and ${ctx.scope.check(`x.${m("tenant")}`, read)}
$$;
${userGrant(`${fn("list_risk_matrices")}(${ctx.idType})`)}

create or replace function ${fn("create_risk")}(tenant ${ctx.idType}, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_matrix uuid;
  v_row ${risks}%rowtype;
begin
  if not ${allowed("create_risk.tenant", write)} then
    ${fail("RISK_FORBIDDEN", "not allowed to create risks")}
  end if;
  v_matrix := coalesce((input ->> 'matrixId')::uuid, ${fn("ensure_risk_matrix")}(create_risk.tenant));
  insert into ${risks} (${r("tenant")}, ${r("matrix")}, ${r("number")}, ${r("title")}, ${r("description")}, ${r("category")}, ${r("cause")}, ${r("consequence")}, ${r("owner")}, ${r("reviewIntervalMonths")})
  values (create_risk.tenant, v_matrix, 'RSK-' || lpad(((select count(*) + 1 from ${risks} x where x.${r("tenant")} = create_risk.tenant))::text, 4, '0'), trim(input ->> 'title'), input ->> 'description', input ->> 'category', input ->> 'cause', input ->> 'consequence', (input ->> 'ownerId')::uuid, (input ->> 'reviewIntervalMonths')::integer)
  returning * into v_row;
  ${ctx.record({
    type: "risk.created",
    payload: `jsonb_build_object('organizationId', v_row.${r("tenant")}, 'riskId', v_row.${r("id")}, 'number', v_row.${r("number")})`,
    subject: `'risks/' || v_row.${r("id")}::text`,
    tenant: `v_row.${r("tenant")}`,
    audit: {
      category: "data",
      targetType: "risk",
      recordId: `v_row.${r("id")}::text`,
      summary: `'created risk ' || v_row.${r("number")}`,
    },
  })}
  return ${riskJson("v_row")};
end;
$$;
${userGrant(`${fn("create_risk")}(${ctx.idType}, jsonb)`)}

create or replace function ${fn("update_risk")}(risk_id uuid, changes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${risks}%rowtype;
  v_changed text[] := '{}';
begin
  select * into v_row from ${risks} x where x.${r("id")} = update_risk.risk_id for update;
  if not found then
    ${fail("RISK_NOT_FOUND", "risk not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${r("tenant")}`, write)} then
    ${fail("RISK_FORBIDDEN", "not allowed to change risks")}
  end if;
  if v_row.${r("status")} = 'closed' then
    ${fail("RISK_CLOSED", "a closed risk can't change", "55000")}
  end if;
  if changes ? 'title' then v_row.${r("title")} := changes ->> 'title'; v_changed := array_append(v_changed, 'title'); end if;
  if changes ? 'description' then v_row.${r("description")} := changes ->> 'description'; v_changed := array_append(v_changed, 'description'); end if;
  if changes ? 'category' then v_row.${r("category")} := changes ->> 'category'; v_changed := array_append(v_changed, 'category'); end if;
  if changes ? 'cause' then v_row.${r("cause")} := changes ->> 'cause'; v_changed := array_append(v_changed, 'cause'); end if;
  if changes ? 'consequence' then v_row.${r("consequence")} := changes ->> 'consequence'; v_changed := array_append(v_changed, 'consequence'); end if;
  if changes ? 'ownerId' then v_row.${r("owner")} := (changes ->> 'ownerId')::uuid; v_changed := array_append(v_changed, 'ownerId'); end if;
  if changes ? 'reviewIntervalMonths' then v_row.${r("reviewIntervalMonths")} := (changes ->> 'reviewIntervalMonths')::integer; v_changed := array_append(v_changed, 'reviewIntervalMonths'); end if;
  update ${risks} x set ${r("title")} = v_row.${r("title")}, ${r("description")} = v_row.${r("description")}, ${r("category")} = v_row.${r("category")}, ${r("cause")} = v_row.${r("cause")}, ${r("consequence")} = v_row.${r("consequence")}, ${r("owner")} = v_row.${r("owner")}, ${r("reviewIntervalMonths")} = v_row.${r("reviewIntervalMonths")}, ${r("updatedAt")} = now()
    where x.${r("id")} = v_row.${r("id")} returning * into v_row;
  ${ctx.record({
    type: "risk.updated",
    payload: `jsonb_build_object('organizationId', v_row.${r("tenant")}, 'riskId', v_row.${r("id")}, 'number', v_row.${r("number")}, 'changed', to_jsonb(v_changed))`,
    subject: `'risks/' || v_row.${r("id")}::text`,
    tenant: `v_row.${r("tenant")}`,
    audit: {
      category: "data",
      targetType: "risk",
      recordId: `v_row.${r("id")}::text`,
      summary: `'changed risk ' || v_row.${r("number")}`,
    },
  })}
  return ${riskJson("v_row")};
end;
$$;
${userGrant(`${fn("update_risk")}(uuid, jsonb)`)}

create or replace function ${fn("assess_risk")}(risk_id uuid, inherent_likelihood integer, inherent_impact integer, residual_likelihood integer, residual_impact integer, rationale text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${risks}%rowtype;
  v_matrix ${matrices}%rowtype;
  v_inherent integer;
  v_residual integer;
  v_assessment ${assessments}%rowtype;
begin
  select * into v_row from ${risks} x where x.${r("id")} = assess_risk.risk_id for update;
  if not found then
    ${fail("RISK_NOT_FOUND", "risk not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${r("tenant")}`, assess)} then
    ${fail("RISK_FORBIDDEN", "not allowed to assess risks")}
  end if;
  if v_row.${r("status")} = 'closed' then
    ${fail("RISK_CLOSED", "a closed risk can't change", "55000")}
  end if;
  select * into v_matrix from ${matrices} x where x.${m("id")} = v_row.${r("matrix")};
  if inherent_likelihood not between 1 and jsonb_array_length(v_matrix.${m("likelihoodLevels")}) or residual_likelihood not between 1 and jsonb_array_length(v_matrix.${m("likelihoodLevels")}) or inherent_impact not between 1 and jsonb_array_length(v_matrix.${m("impactLevels")}) or residual_impact not between 1 and jsonb_array_length(v_matrix.${m("impactLevels")}) then
    ${fail("RISK_LEVEL_OUT_OF_RANGE", "a level is out of range", "22023")}
  end if;
  v_inherent := case when v_matrix.${m("scoring")} = 'sum' then inherent_likelihood + inherent_impact else inherent_likelihood * inherent_impact end;
  v_residual := case when v_matrix.${m("scoring")} = 'sum' then residual_likelihood + residual_impact else residual_likelihood * residual_impact end;
  insert into ${assessments} (${a("tenant")}, ${a("risk")}, ${a("inherentLikelihood")}, ${a("inherentImpact")}, ${a("inherentScore")}, ${a("inherentBand")}, ${a("residualLikelihood")}, ${a("residualImpact")}, ${a("residualScore")}, ${a("residualBand")}, ${a("rationale")})
  values (v_row.${r("tenant")}, v_row.${r("id")}, inherent_likelihood, inherent_impact, v_inherent, ${band("v_inherent", `v_matrix.${m("bands")}`)}, residual_likelihood, residual_impact, v_residual, ${band("v_residual", `v_matrix.${m("bands")}`)}, assess_risk.rationale)
  returning * into v_assessment;
  update ${risks} x set ${r("inherentLikelihood")} = inherent_likelihood, ${r("inherentImpact")} = inherent_impact, ${r("inherentScore")} = v_inherent, ${r("inherentBand")} = v_assessment.${a("inherentBand")}, ${r("residualLikelihood")} = residual_likelihood, ${r("residualImpact")} = residual_impact, ${r("residualScore")} = v_residual, ${r("residualBand")} = v_assessment.${a("residualBand")}, ${r("currentAssessment")} = v_assessment.${a("id")}, ${r("status")} = case when ${r("status")} = 'identified' then 'assessed' else ${r("status")} end, ${r("nextReviewOn")} = case when ${r("reviewIntervalMonths")} is null then ${r("nextReviewOn")} else current_date + make_interval(months => ${r("reviewIntervalMonths")}) end, ${r("updatedAt")} = now()
    where x.${r("id")} = v_row.${r("id")} returning * into v_row;
  ${ctx.record({
    type: "risk.assessed",
    payload: `jsonb_build_object('organizationId', v_row.${r("tenant")}, 'riskId', v_row.${r("id")}, 'number', v_row.${r("number")}, 'inherentBand', v_row.${r("inherentBand")}, 'residualBand', v_row.${r("residualBand")})`,
    subject: `'risks/' || v_row.${r("id")}::text`,
    tenant: `v_row.${r("tenant")}`,
    audit: {
      category: "data",
      targetType: "risk",
      recordId: `v_row.${r("id")}::text`,
      summary: `'assessed risk ' || v_row.${r("number")}`,
    },
  })}
  return ${riskJson("v_row")};
end;
$$;
${userGrant(`${fn("assess_risk")}(uuid, integer, integer, integer, integer, text)`)}

create or replace function ${fn("set_risk_treatment")}(risk_id uuid, treatment text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${risks}%rowtype;
begin
  select * into v_row from ${risks} x where x.${r("id")} = set_risk_treatment.risk_id for update;
  if not found then
    ${fail("RISK_NOT_FOUND", "risk not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${r("tenant")}`, write)} then
    ${fail("RISK_FORBIDDEN", "not allowed to change risks")}
  end if;
  if set_risk_treatment.treatment not in ('mitigate', 'accept', 'transfer', 'avoid') then
    ${fail("RISK_INVALID", "the treatment is invalid", "22023")}
  end if;
  if set_risk_treatment.treatment = 'accept' and not ${allowed(`v_row.${r("tenant")}`, manage)} then
    ${fail("RISK_FORBIDDEN", "accepting a risk needs risks.manage")}
  end if;
  update ${risks} x set ${r("treatment")} = set_risk_treatment.treatment, ${r("status")} = case when set_risk_treatment.treatment in ('mitigate', 'transfer') then 'treating' when set_risk_treatment.treatment = 'accept' then 'accepted' else 'closed' end, ${r("updatedAt")} = now()
    where x.${r("id")} = v_row.${r("id")} returning * into v_row;
  ${ctx.record({
    type: "risk.treatment_changed",
    payload: `jsonb_build_object('organizationId', v_row.${r("tenant")}, 'riskId', v_row.${r("id")}, 'number', v_row.${r("number")}, 'treatment', v_row.${r("treatment")})`,
    subject: `'risks/' || v_row.${r("id")}::text`,
    tenant: `v_row.${r("tenant")}`,
    audit: {
      category: "data",
      targetType: "risk",
      recordId: `v_row.${r("id")}::text`,
      summary: `'changed treatment of ' || v_row.${r("number")}`,
    },
  })}
  return ${riskJson("v_row")};
end;
$$;
${userGrant(`${fn("set_risk_treatment")}(uuid, text, text)`)}

create or replace function ${fn("review_risk")}(risk_id uuid, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${risks}%rowtype;
begin
  select * into v_row from ${risks} x where x.${r("id")} = review_risk.risk_id for update;
  if not found then
    ${fail("RISK_NOT_FOUND", "risk not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${r("tenant")}`, write)} then
    ${fail("RISK_FORBIDDEN", "not allowed to review risks")}
  end if;
  update ${risks} x set ${r("nextReviewOn")} = case when ${r("reviewIntervalMonths")} is null then ${r("nextReviewOn")} else current_date + make_interval(months => ${r("reviewIntervalMonths")}) end, ${r("updatedAt")} = now()
    where x.${r("id")} = v_row.${r("id")} returning * into v_row;
  ${ctx.record({
    type: "risk.reviewed",
    payload: `jsonb_build_object('organizationId', v_row.${r("tenant")}, 'riskId', v_row.${r("id")}, 'number', v_row.${r("number")})`,
    subject: `'risks/' || v_row.${r("id")}::text`,
    tenant: `v_row.${r("tenant")}`,
    audit: {
      category: "data",
      targetType: "risk",
      recordId: `v_row.${r("id")}::text`,
      summary: `'reviewed risk ' || v_row.${r("number")}`,
    },
  })}
  return ${riskJson("v_row")};
end;
$$;
${userGrant(`${fn("review_risk")}(uuid, text)`)}

create or replace function ${fn("close_risk")}(risk_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${risks}%rowtype;
begin
  select * into v_row from ${risks} x where x.${r("id")} = close_risk.risk_id for update;
  if not found then
    ${fail("RISK_NOT_FOUND", "risk not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${r("tenant")}`, manage)} then
    ${fail("RISK_FORBIDDEN", "not allowed to close risks")}
  end if;
  update ${risks} x set ${r("status")} = 'closed', ${r("updatedAt")} = now() where x.${r("id")} = v_row.${r("id")} returning * into v_row;
  ${ctx.record({
    type: "risk.closed",
    payload: `jsonb_build_object('organizationId', v_row.${r("tenant")}, 'riskId', v_row.${r("id")}, 'number', v_row.${r("number")})`,
    subject: `'risks/' || v_row.${r("id")}::text`,
    tenant: `v_row.${r("tenant")}`,
    audit: {
      category: "data",
      targetType: "risk",
      recordId: `v_row.${r("id")}::text`,
      summary: `'closed risk ' || v_row.${r("number")}`,
    },
  })}
  return ${riskJson("v_row")};
end;
$$;
${userGrant(`${fn("close_risk")}(uuid, text)`)}

create or replace function ${fn("get_risk")}(risk_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${risks}%rowtype;
  v_assessments jsonb;
begin
  select * into v_row from ${risks} x where x.${r("id")} = get_risk.risk_id;
  if not found then
    ${fail("RISK_NOT_FOUND", "risk not found", "P0002")}
  end if;
  if not ${allowed(`v_row.${r("tenant")}`, read)} then
    ${fail("RISK_FORBIDDEN", "not allowed to read risks")}
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', x.${a("id")}, 'inherentScore', x.${a("inherentScore")}, 'inherentBand', x.${a("inherentBand")}, 'residualScore', x.${a("residualScore")}, 'residualBand', x.${a("residualBand")}, 'rationale', x.${a("rationale")}, 'assessedAt', x.${a("assessedAt")}) order by x.${a("assessedAt")} desc), '[]'::jsonb) into v_assessments from ${assessments} x where x.${a("risk")} = v_row.${r("id")};
  return ${riskJson("v_row")} || jsonb_build_object('assessments', v_assessments);
end;
$$;
${userGrant(`${fn("get_risk")}(uuid)`)}

create or replace function ${fn("list_risks")}(tenant ${ctx.idType}, filters jsonb default '{}')
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(${riskJson("x")} order by x.${r("createdAt")} desc), '[]'::jsonb)
  from ${risks} x
  where x.${r("tenant")} = $1
    and ${ctx.scope.check(`x.${r("tenant")}`, read)}
    and (not (filters ? 'category') or x.${r("category")} = filters ->> 'category')
    and (not (filters ? 'status') or x.${r("status")} = filters ->> 'status')
    and (not (filters ? 'owner') or x.${r("owner")} = (filters ->> 'owner')::uuid)
    and (not (filters ? 'reviewDue') or (filters ->> 'reviewDue')::boolean = false or (x.${r("nextReviewOn")} is not null and x.${r("nextReviewOn")} <= current_date))
    and (not (filters ? 'search') or x.${r("title")} ilike '%' || (filters ->> 'search') || '%' or x.${r("number")} ilike '%' || (filters ->> 'search') || '%')
$$;
${userGrant(`${fn("list_risks")}(${ctx.idType}, jsonb)`)}

create or replace function ${fn("risk_heatmap")}(tenant ${ctx.idType}, matrix_id uuid default null, basis text default 'residual')
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'matrix', ${matrixJson("m")},
    'cells', coalesce(jsonb_agg(jsonb_build_object('likelihood', l, 'impact', i, 'count', c, 'riskIds', ids)), '[]'::jsonb)
  )
  from (
    select
      case when $3 = 'inherent' then x.${r("inherentLikelihood")} else x.${r("residualLikelihood")} end as l,
      case when $3 = 'inherent' then x.${r("inherentImpact")} else x.${r("residualImpact")} end as i,
      count(*) as c,
      jsonb_agg(x.${r("id")}) as ids
    from ${risks} x
    where x.${r("tenant")} = $1 and x.${r("status")} <> 'closed' and ${ctx.scope.check(`x.${r("tenant")}`, read)}
    group by 1, 2
  ) s
  cross join (select * from ${matrices} where ${m("id")} = coalesce($2, (select ${m("id")} from ${matrices} where ${m("tenant")} = $1 and ${m("isDefault")} limit 1))) m
  group by m.${m("id")}, m.${m("tenant")}, m.${m("key")}, m.${m("name")}, m.${m("likelihoodLevels")}, m.${m("impactLevels")}, m.${m("bands")}, m.${m("scoring")}, m.${m("isDefault")}
$$;
${userGrant(`${fn("risk_heatmap")}(${ctx.idType}, uuid, text)`)}

create or replace function ${fn("notify_due_risk_reviews")}()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row record;
  v_count integer := 0;
begin
  for v_row in select x.* from ${risks} x where x.${r("status")} <> 'closed' and x.${r("nextReviewOn")} is not null and x.${r("nextReviewOn")} <= current_date
  loop
    ${ctx.record({
      type: "risk.review_reminded",
      payload: `jsonb_build_object('organizationId', v_row.${r("tenant")}, 'riskId', v_row.${r("id")}, 'number', v_row.${r("number")}, 'nextReviewOn', v_row.${r("nextReviewOn")}::text)`,
      subject: `'risks/' || v_row.${r("id")}::text`,
      tenant: `v_row.${r("tenant")}`,
      audit: {
        category: "data",
        targetType: "risk",
        recordId: `v_row.${r("id")}::text`,
        summary: `'risk review due ' || v_row.${r("number")}`,
      },
    })}
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${userGrant(`${fn("notify_due_risk_reviews")}()`)}
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  return `${schemaPreamble(ctx)}
-- Risks: matrices, a register, versioned assessments, treatment, reviews and a
-- heatmap.
${tables(ctx)}${functions(ctx)}`;
}

function contract(_ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "save_risk_matrix",
      args: ["{id}", "text", "text", "jsonb", "jsonb", "jsonb", "text", "boolean", "uuid"],
      returns: "jsonb",
    },
    { name: "list_risk_matrices", args: ["{id}"], returns: "jsonb" },
    { name: "create_risk", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "update_risk", args: ["uuid", "jsonb"], returns: "jsonb" },
    {
      name: "assess_risk",
      args: ["uuid", "integer", "integer", "integer", "integer", "text"],
      returns: "jsonb",
    },
    {
      name: "set_risk_treatment",
      args: ["uuid", "text", "text"],
      returns: "jsonb",
    },
    { name: "review_risk", args: ["uuid", "text"], returns: "jsonb" },
    { name: "close_risk", args: ["uuid", "text"], returns: "jsonb" },
    { name: "get_risk", args: ["uuid"], returns: "jsonb" },
    { name: "list_risks", args: ["{id}", "jsonb"], returns: "jsonb" },
    {
      name: "risk_heatmap",
      args: ["{id}", "uuid", "text"],
      returns: "jsonb",
    },
    { name: "notify_due_risk_reviews", args: [], returns: "integer" },
  ];
}

export const RISKS: BlockSqlDefinition = {
  name: "risks",
  scopes: ["tenant"],
  title: "Risks",
  description:
    "Risk matrices, a register, versioned assessments, treatment decisions, reviews and a heatmap.",
  requires: ["memberships", "permissions"],
  integrates: ["outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
