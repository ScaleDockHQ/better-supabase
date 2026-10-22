import type { ScoresEvents } from "../../blocks/scores/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { lockTable, schemaPreamble } from "../shared.ts";
import { scoresFunctions } from "./scores-functions.ts";

const MODEL_PAYLOAD = [
  "organizationId",
  "id",
  "key",
  "subjectType",
  "version",
] as const;

const EVENTS: BlockSqlEvents<ScoresEvents> = {
  "score_model.saved": { subject: "score-models", payload: MODEL_PAYLOAD },
  "score_model.deleted": { subject: "score-models", payload: MODEL_PAYLOAD },
  "score.changed": {
    subject: "scores",
    payload: [
      "organizationId",
      "modelId",
      "modelKey",
      "subjectType",
      "subjectId",
      "score",
      "previousScore",
      "band",
      "previousBand",
    ],
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    score_model: { table: "models", singular: "score_model", primary: true },
  },
  events: EVENTS,
  options: ["maxRules", "maxMetrics"],
  tables: {
    models: {
      name: "score_models",
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        key: "key",
        name: "name",
        description: "description",
        subjectType: "subject_type",
        rules: "rules",
        metrics: "metrics",
        bands: "bands",
        enabled: "enabled",
        version: "version",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    versions: {
      name: "score_model_versions",
      lifecycle: { tenant: "tenant", user: "savedBy", export: true },
      columns: {
        model: "model_id",
        version: "version",
        tenant: "tenant_id",
        rules: "rules",
        metrics: "metrics",
        bands: "bands",
        savedBy: "saved_by",
        savedAt: "saved_at",
      },
    },
    scores: {
      name: "scores",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        model: "model_id",
        modelVersion: "model_version",
        subjectType: "subject_type",
        subjectId: "subject_id",
        score: "score",
        band: "band",
        breakdown: "breakdown",
        current: "is_current",
        computedAt: "computed_at",
      },
    },
  },
};

const jsonArray = (column: string): string =>
  `${column} jsonb not null default '[]'::jsonb check (jsonb_typeof(${column}) = 'array')`;

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const models = ctx.table("models");
  const versions = ctx.table("versions");
  const scores = ctx.table("scores");
  const m = (column: string): string => ctx.col("models", column);
  const v = (column: string): string => ctx.col("versions", column);
  const s = (column: string): string => ctx.col("scores", column);
  const read = ctx.permission("read", "scores.read");

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const tables = ctx.manages
    ? `create table if not exists ${models} (
  ${m("id")} uuid primary key default gen_random_uuid(),
  ${m("tenant")} ${ctx.idType} not null,
  -- lead, health, or the app's own key.
  ${m("key")} text not null check (${m("key")} ~ '^[a-z][a-z0-9_-]{0,62}$'),
  ${m("name")} text not null check (length(${m("name")}) between 1 and 200),
  ${m("description")} text check (${m("description")} is null or length(${m("description")}) <= 2000),
  ${m("subjectType")} text not null check (${m("subjectType")} ~ '^[a-z][a-z0-9_]{0,62}$'),
  -- [{ id, label, conditions, points }]: a filter tree over the rules field
  -- catalog and the points a match adds.
  ${jsonArray(m("rules"))},
  -- [{ id, label, source, field, weight, cap }]: a number times its weight.
  ${jsonArray(m("metrics"))},
  -- [{ label, min }], highest min first: the first band the score reaches.
  ${jsonArray(m("bands"))},
  ${m("enabled")} boolean not null default true,
  ${m("version")} integer not null default 1,
  ${m("createdBy")} uuid,
  ${m("createdAt")} timestamptz not null default now(),
  ${m("updatedAt")} timestamptz not null default now(),
  unique (${m("tenant")}, ${m("key")})
);
create index if not exists ${name("models", "subject_idx")} on ${models} (${m("tenant")}, ${m("subjectType")});

create table if not exists ${versions} (
  ${v("model")} uuid not null references ${models} (${m("id")}) on delete cascade,
  ${v("version")} integer not null,
  ${v("tenant")} ${ctx.idType} not null,
  ${jsonArray(v("rules"))},
  ${jsonArray(v("metrics"))},
  ${jsonArray(v("bands"))},
  ${v("savedBy")} uuid,
  ${v("savedAt")} timestamptz not null default now(),
  primary key (${v("model")}, ${v("version")})
);

create table if not exists ${scores} (
  ${s("id")} uuid primary key default gen_random_uuid(),
  ${s("tenant")} ${ctx.idType} not null,
  ${s("model")} uuid not null references ${models} (${m("id")}) on delete cascade,
  ${s("modelVersion")} integer not null,
  ${s("subjectType")} text not null,
  ${s("subjectId")} text not null,
  ${s("score")} numeric not null,
  ${s("band")} text,
  -- { rules: [{ id, label, matched, points }], metrics: [{ id, label, value, points }] }
  ${s("breakdown")} jsonb not null default '{}'::jsonb check (jsonb_typeof(${s("breakdown")}) = 'object'),
  ${s("current")} boolean not null default true,
  ${s("computedAt")} timestamptz not null default now()
);
create unique index if not exists ${name("scores", "current_idx")} on ${scores} (${s("model")}, ${s("subjectType")}, ${s("subjectId")}) where ${s("current")};
create index if not exists ${name("scores", "rank_idx")} on ${scores} (${s("tenant")}, ${s("model")}, ${s("score")} desc) where ${s("current")};
create index if not exists ${name("scores", "subject_idx")} on ${scores} (${s("tenant")}, ${s("subjectType")}, ${s("subjectId")}) where ${s("current")};
create index if not exists ${name("scores", "history_idx")} on ${scores} (${s("model")}, ${s("subjectType")}, ${s("subjectId")}, ${s("computedAt")} desc);

${lockTable(models, { read: true })}
drop policy if exists ${name("models", "read")} on ${models};
create policy ${name("models", "read")} on ${models} for select to authenticated
  using (${ctx.scope.check(m("tenant"), read)});
${lockTable(versions, { read: true })}
drop policy if exists ${name("versions", "read")} on ${versions};
create policy ${name("versions", "read")} on ${versions} for select to authenticated
  using (${ctx.scope.check(v("tenant"), read)});
${lockTable(scores, { read: true })}
drop policy if exists ${name("scores", "read")} on ${scores};
create policy ${name("scores", "read")} on ${scores} for select to authenticated
  using (${ctx.scope.check(s("tenant"), read)});
`
    : "";

  return `${schemaPreamble(ctx)}
${tables}
${scoresFunctions(ctx)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    { name: "save_score_model", args: ["{id}", "jsonb"], returns: "jsonb" },
    {
      name: "compute_score",
      args: ["{id}", "text", "text", "text", "jsonb", "text"],
      returns: "jsonb",
    },
    {
      name: "subject_scores",
      args: ["{id}", "text", "text"],
      returns: "jsonb",
    },
  ];
}

export const SCORES: BlockSqlDefinition = {
  name: "scores",
  scopes: ["tenant"],
  title: "Scores",
  description:
    "Tenant-editable scoring models: rules (a filter tree over the rules field catalog worth points) and metrics (a number times a weight, or a record's vote score) that write versioned scores with bands to any subject. Lead scoring and health scoring are models.",
  requires: ["memberships", "permissions", "automations"],
  integrates: ["reactions", "outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
