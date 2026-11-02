import type { RisksEvents } from "../../blocks/risks/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockContributes } from "../contributions.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { entityType } from "../resolved-names.ts";
import { addExtraColumns, lockTable, schemaPreamble } from "../shared.ts";
import { riskAssessFunctions } from "./risks-assess.ts";
import { riskFunctions } from "./risks-functions.ts";
import {
  RISK_SCORINGS,
  RISK_STATUSES,
  RISK_TREATMENTS,
  risksSql,
} from "./risks-sql.ts";

const RISK = ["organizationId", "id", "number", "title", "status"] as const;
const risk = { subject: "risks", payload: RISK } as const;

const matrix = {
  subject: "risk-matrices",
  payload: ["organizationId", "id", "key", "name", "isDefault"],
} as const;

const EVENTS: BlockSqlEvents<RisksEvents> = {
  "risk_matrix.created": matrix,
  "risk_matrix.updated": matrix,
  "risk.created": risk,
  "risk.updated": risk,
  "risk.assessed": {
    subject: "risks",
    payload: [
      ...RISK,
      "assessmentId",
      "inherentScore",
      "inherentBand",
      "residualScore",
      "residualBand",
    ],
  },
  "risk.treatment_changed": {
    subject: "risks",
    payload: [...RISK, "treatment", "note"],
  },
  "risk.reviewed": {
    subject: "risks",
    payload: [...RISK, "nextReviewOn", "note"],
  },
  "risk.closed": { subject: "risks", payload: [...RISK, "reason"] },
  "risk.review_date_reached": {
    subject: "risks",
    payload: [...RISK, "ownerId", "nextReviewOn"],
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
        deletedAt: "archivedAt",
        permissions: { read: "read", write: "write" },
        search: {
          title: "title",
          body: ["number", "description", "cause", "consequence"],
        },
      },
    },
    risk_matrix: {
      table: "matrices",
      singular: "risk_matrix",
      plural: "risk_matrices",
    },
    risk_assessment: { table: "assessments", singular: "risk_assessment" },
  },
  events: EVENTS,
  hooks: [
    "before_risk_create",
    "after_risk_create",
    "before_risk_assess",
    "after_risk_assess",
    "before_risk_close",
    "after_risk_close",
  ],
  options: ["categories", "defaultMatrix", "extraColumns"],
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
    },
    risks: {
      name: "risks",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        number: "number",
        sequence: "sequence",
        matrix: "matrix_id",
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
        reviewedAt: "reviewed_at",
        reviewNotifiedFor: "review_notified_for",
        inherentLikelihood: "inherent_likelihood",
        inherentImpact: "inherent_impact",
        inherentScore: "inherent_score",
        inherentBand: "inherent_band",
        residualLikelihood: "residual_likelihood",
        residualImpact: "residual_impact",
        residualScore: "residual_score",
        residualBand: "residual_band",
        currentAssessment: "current_assessment_id",
        closedAt: "closed_at",
        archivedAt: "archived_at",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
      optional: ["description", "cause", "consequence", "createdBy"],
    },
    assessments: {
      name: "risk_assessments",
      app: {},
      lifecycle: { tenant: "tenant", user: "assessedBy", export: true },
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
        version: "version_id",
        assessedBy: "assessed_by",
        assessedAt: "assessed_at",
      },
      optional: ["rationale", "version"],
    },
  },
};

const list = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

function tables(ctx: BlockSqlContext): string {
  const q = risksSql(ctx);
  const { m, r, a, matrices, risks, assessments } = q;

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const opt = (logical: string, column: string, line: () => string): string =>
    ctx.has(logical, column) ? `\n  ${line()},` : "";

  const appKey = (logical: string, what: string, columns: string): string =>
    ctx.owns(logical)
      ? ""
      : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName(logical).name}_${what}_key`)} on ${ctx.table(logical)} (${columns});`;

  const readPolicy = (logical: string, tenant: string): string =>
    renderPolicy(
      makePolicy({
        table: ctx.table(logical),
        name: ctx.owns(logical)
          ? name(logical, "read")
          : sqlIdent(`bsb_${ctx.tableName(logical).name}_read`),
        command: "select",
        roles: ["authenticated"],
        using: ctx.scope.check(tenant, q.read),
      }),
      { drop: true, target: ctx.table(logical) },
    );

  const level = (column: string): string =>
    `${column} integer check (${column} is null or ${column} between 1 and 10)`;

  const score = (column: string): string =>
    `${column} integer check (${column} is null or ${column} between 1 and 100)`;

  const text = (column: string, max: number): string =>
    `${column} text check (${column} is null or length(${column}) <= ${String(max)})`;

  const versions = q.versions;

  const versionRef = versions.owns("versions")
    ? ` references ${versions.table("versions")} (${versions.col("versions", "id")}) on delete set null`
    : "";

  return `
create table if not exists ${matrices} (
  ${m("id")} uuid primary key default gen_random_uuid(),
  ${m("tenant")} ${ctx.idType} not null,
  ${m("key")} text not null check (${m("key")} ~ '^[a-z][a-z0-9_-]{0,62}$'),
  ${m("name")} text not null check (length(${m("name")}) between 1 and 200),
  -- [{ value, label }] with values 1 to n; save_risk_matrix checks the shape.
  ${m("likelihoodLevels")} jsonb not null check (jsonb_typeof(${m("likelihoodLevels")}) = 'array'),
  ${m("impactLevels")} jsonb not null check (jsonb_typeof(${m("impactLevels")}) = 'array'),
  -- [{ key, label, min, max }] covering every score once.
  ${m("bands")} jsonb not null check (jsonb_typeof(${m("bands")}) = 'array'),
  ${m("scoring")} text not null default 'product' check (${m("scoring")} in (${list(RISK_SCORINGS)})),
  ${m("isDefault")} boolean not null default false,
  ${m("createdAt")} timestamptz not null default now(),
  ${m("updatedAt")} timestamptz not null default now(),
  unique (${m("tenant")}, ${m("key")}),
  unique (${m("tenant")}, ${m("id")})
);${appKey("matrices", "tenant_key", `${m("tenant")}, ${m("key")}`)}${appKey("matrices", "tenant_id", `${m("tenant")}, ${m("id")}`)}
create unique index if not exists ${name("matrices", "default_key")} on ${matrices} (${m("tenant")}) where ${m("isDefault")};
${lockTable(matrices, { read: true })}
${readPolicy("matrices", m("tenant"))}

create table if not exists ${risks} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${ctx.idType} not null,
  -- RSK-0001, from the numbering block when it numbers risks.
  ${r("number")} text not null check (length(${r("number")}) between 1 and 100),
  ${r("sequence")} bigint not null,
  ${r("matrix")} uuid not null,
  ${r("title")} text not null check (length(${r("title")}) between 1 and 300),${opt("risks", "description", () => text(r("description"), 10_000))}
  -- One of options.categories; the functions check it.
  ${r("category")} text not null check (length(${r("category")}) between 1 and 63),${opt("risks", "cause", () => text(r("cause"), 4000))}${opt("risks", "consequence", () => text(r("consequence"), 4000))}
  ${r("owner")} uuid,
  ${r("status")} text not null default 'identified' check (${r("status")} in (${list(RISK_STATUSES)})),
  ${r("treatment")} text check (${r("treatment")} is null or ${r("treatment")} in (${list(RISK_TREATMENTS)})),
  -- An assessment or a review moves next_review_on this many months ahead (12 when null).
  ${r("reviewIntervalMonths")} integer check (${r("reviewIntervalMonths")} is null or ${r("reviewIntervalMonths")} between 1 and 120),
  ${r("nextReviewOn")} date,
  ${r("reviewedAt")} timestamptz,
  -- The review date notify_due_risk_reviews last reported, so each lapse notifies once.
  ${r("reviewNotifiedFor")} date,
  ${level(r("inherentLikelihood"))},
  ${level(r("inherentImpact"))},
  ${score(r("inherentScore"))},
  ${r("inherentBand")} text,
  ${level(r("residualLikelihood"))},
  ${level(r("residualImpact"))},
  ${score(r("residualScore"))},
  ${r("residualBand")} text,
  ${r("currentAssessment")} uuid,
  ${r("closedAt")} timestamptz,
  ${r("archivedAt")} timestamptz,${opt("risks", "createdBy", () => `${r("createdBy")} uuid`)}
  ${r("createdAt")} timestamptz not null default now(),
  ${r("updatedAt")} timestamptz not null default now(),
  unique (${r("tenant")}, ${r("number")}),
  unique (${r("tenant")}, ${r("id")}),
  check (${r("status")} <> 'closed' or ${r("closedAt")} is not null),
  foreign key (${r("tenant")}, ${r("matrix")}) references ${matrices} (${m("tenant")}, ${m("id")}) on delete restrict
);${addExtraColumns(risks, q.extras)}${appKey("risks", "tenant_number", `${r("tenant")}, ${r("number")}`)}${appKey("risks", "tenant_id", `${r("tenant")}, ${r("id")}`)}
create index if not exists ${name("risks", "tenant_idx")} on ${risks} (${r("tenant")}, ${r("status")}, ${r("residualScore")} desc);
create index if not exists ${name("risks", "matrix_idx")} on ${risks} (${r("tenant")}, ${r("matrix")});
create index if not exists ${name("risks", "owner_idx")} on ${risks} (${r("tenant")}, ${r("owner")}) where ${r("owner")} is not null;
create index if not exists ${name("risks", "review_idx")} on ${risks} (${r("nextReviewOn")}) where ${r("status")} <> 'closed';
${lockTable(risks, { read: true })}
${readPolicy("risks", r("tenant"))}

create table if not exists ${assessments} (
  ${a("id")} uuid primary key default gen_random_uuid(),
  ${a("tenant")} ${ctx.idType} not null,
  ${a("risk")} uuid not null,
  ${level(a("inherentLikelihood"))} not null,
  ${level(a("inherentImpact"))} not null,
  ${score(a("inherentScore"))} not null,
  ${a("inherentBand")} text not null,
  ${level(a("residualLikelihood"))} not null,
  ${level(a("residualImpact"))} not null,
  ${score(a("residualScore"))} not null,
  ${a("residualBand")} text not null,${opt("assessments", "rationale", () => text(a("rationale"), 10_000))}${opt("assessments", "version", () => `${a("version")} uuid${versionRef}`)}
  ${a("assessedBy")} uuid,
  ${a("assessedAt")} timestamptz not null default now(),
  foreign key (${a("tenant")}, ${a("risk")}) references ${risks} (${r("tenant")}, ${r("id")}) on delete cascade
);
create index if not exists ${name("assessments", "history_idx")} on ${assessments} (${a("tenant")}, ${a("risk")}, ${a("assessedAt")} desc);
${ctx.has("assessments", "version") ? `create index if not exists ${name("assessments", "version_idx")} on ${assessments} (${a("version")}) where ${a("version")} is not null;\n` : ""}${lockTable(assessments, { read: true })}
${readPolicy("assessments", a("tenant"))}
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  if (ctx.of("versions").mode === "custom") {
    throw new TypeError(
      "blocks.risks needs the versions tables to snapshot assessments; versions can't be in custom mode",
    );
  }

  return `${schemaPreamble(ctx)}
-- A risk register per organization: risks scored on a likelihood by impact
-- matrix, assessed before and after controls, treated, reviewed and closed.
${tables(ctx)}
${riskFunctions(ctx)}
${riskAssessFunctions(ctx)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "save_risk_matrix",
      args: [
        "{id}",
        "text",
        "text",
        "jsonb",
        "jsonb",
        "jsonb",
        "text",
        "boolean",
        "uuid",
      ],
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
    { name: "risk_heatmap", args: ["{id}", "uuid", "text"], returns: "jsonb" },
    { name: "notify_due_risk_reviews", args: [], returns: "integer" },
  ];
}

/** A subject type of another block, after its renames when it's installed. */
const typeOf = (
  own: BlockSqlContext,
  module: string,
  entity: string,
): string =>
  own.installed(module) ? entityType(own.of(module).resolved, entity) : entity;

const CONTRIBUTES: BlockContributes = {
  numbering: (own) => [
    {
      entity: own.resolved.entityNaming.rename("risk"),
      entry: { period: "none", format: "RSK-{n:4}" },
    },
  ],
  relations: (own) => [
    {
      kind: "mitigated_by",
      inverse: "mitigates",
      types: {
        source: [own.naming.rename("risk")],
        // Controls, tasks and drive files are a risk's barriers.
        target: [
          typeOf(own, "compliance", "control"),
          typeOf(own, "tasks", "task"),
          "drive_node",
        ],
      },
    },
    {
      kind: "materialized_as",
      inverse: "materializes",
      types: { source: [own.naming.rename("risk")], target: ["case"] },
    },
  ],
};

export const RISKS: BlockSqlDefinition = {
  contributes: CONTRIBUTES,
  name: "risks",
  scopes: ["tenant"],
  title: "Risks",
  description:
    "A risk register per organization: risks numbered RSK-0001, scored on a configurable likelihood by impact matrix before and after controls, with an assessment history snapshotted in versions, treatment, scheduled reviews, barriers linked through relations, and a heatmap.",
  requires: ["memberships", "permissions", "subjects", "versions"],
  integrates: [
    "compliance",
    "tasks",
    "relations",
    "numbering",
    "notifications",
    "outbox",
    "audit",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
  seeds: {
    // The matrix `options.defaultMatrix` describes; `ensure_risk_matrix` seeds
    // it lazily when an organization has none.
    defaults: (ctx) => {
      const q = risksSql(ctx);
      const d = q.defaultMatrix;

      return [
        {
          table: q.matrices,
          tenantColumn: q.m("tenant"),
          key: [q.m("key")],
          rows: [
            {
              values: {
                [q.m("key")]: d.key,
                [q.m("name")]: d.name,
                [q.m("likelihoodLevels")]: { json: d.likelihoodLevels },
                [q.m("impactLevels")]: { json: d.impactLevels },
                [q.m("bands")]: { json: d.bands },
                [q.m("scoring")]: d.scoring,
                // Only the first matrix becomes the default.
                [q.m("isDefault")]: {
                  sql: `not exists (select 1 from ${q.matrices} d where d.${sqlIdent(q.m("tenant"))} = p_tenant and d.${sqlIdent(q.m("isDefault"))})`,
                },
              },
            },
          ],
        },
      ];
    },
  },
};
