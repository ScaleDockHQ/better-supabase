import type { ClinicalDecisionSupportEvents } from "../../blocks/clinical-decision-support/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { lockTable, schemaPreamble } from "../shared.ts";
import { decisionSupportEvaluation } from "./clinical-decision-support-evaluate.ts";
import { decisionSupportFunctions } from "./clinical-decision-support-functions.ts";
import { decisionSupportSql } from "./clinical-decision-support-sql.ts";
import {
  CARE_ALERT_KINDS,
  CARE_ALERT_SEVERITIES,
  CARE_ALERT_STATUSES,
  CARE_RULE_KINDS,
} from "./clinical-decision-support-values.ts";

const alert = {
  subject: "care-alerts",
  payload: [
    "organizationId",
    "id",
    "subjectType",
    "subjectId",
    "kind",
    "severity",
    "source",
    "status",
  ],
} as const;

const rule = {
  subject: "care-rules",
  payload: ["organizationId", "id", "kind", "severity"],
} as const;

const EVENTS: BlockSqlEvents<ClinicalDecisionSupportEvents> = {
  "care_alert.raised": alert,
  "care_alert.decided": alert,
  "care_alert.resolved": alert,
  "care_rule.created": rule,
  "care_rule.updated": rule,
  "care_rule.deleted": rule,
};

const NAMES: BlockSqlNames = {
  entities: {
    care_alert: { table: "alerts", singular: "care_alert", primary: true },
    care_rule: { table: "rules", singular: "care_rule" },
  },
  events: EVENTS,
  hooks: ["before_care_alert_decide", "after_care_alert_decide"],
  options: [],
  tables: {
    rules: {
      name: "care_rules",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        kind: "kind",
        medicationIds: "medication_ids",
        minDose: "min_dose",
        maxDose: "max_dose",
        maxPerDay: "max_per_day",
        severity: "severity",
        message: "message",
        active: "active",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    alerts: {
      name: "care_alerts",
      app: {},
      lifecycle: { tenant: "tenant", user: "decidedBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        kind: "kind",
        severity: "severity",
        source: "source",
        rule: "rule_id",
        orderIds: "order_ids",
        message: "message",
        details: "details",
        fingerprint: "fingerprint",
        status: "status",
        decidedBy: "decided_by",
        decidedAt: "decided_at",
        decisionReason: "decision_reason",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
  },
};

const quoted = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

function tables(ctx: BlockSqlContext): string {
  const sql = decisionSupportSql(ctx);
  const { r, a } = sql;

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

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
        using: ctx.scope.check(tenant, sql.read),
      }),
      { drop: true, target: ctx.table(logical) },
    );

  return `
-- A tenant rule of the built-in set. A dose_range rule bounds the dose of one
-- medication (per dose, or per day with max_per_day), an interaction rule names
-- two medications that must not be active together and a duplicate_therapy rule
-- names the medications of one therapy group.
create table if not exists ${sql.rules} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${ctx.idType} not null,
  ${r("kind")} text not null check (${r("kind")} in (${quoted(CARE_RULE_KINDS)})),
  ${r("medicationIds")} uuid[] not null default '{}',
  ${r("minDose")} numeric check (${r("minDose")} is null or ${r("minDose")} >= 0),
  ${r("maxDose")} numeric check (${r("maxDose")} is null or ${r("maxDose")} > 0),
  ${r("maxPerDay")} numeric check (${r("maxPerDay")} is null or ${r("maxPerDay")} > 0),
  ${r("severity")} text not null default 'warning' check (${r("severity")} in (${quoted(CARE_ALERT_SEVERITIES)})),
  ${r("message")} text check (${r("message")} is null or length(${r("message")}) <= 1000),
  ${r("active")} boolean not null default true,
  ${r("createdAt")} timestamptz not null default now(),
  ${r("updatedAt")} timestamptz not null default now(),
  check (
    (${r("kind")} = 'dose_range' and cardinality(${r("medicationIds")}) = 1 and (${r("minDose")} is not null or ${r("maxDose")} is not null or ${r("maxPerDay")} is not null))
    or (${r("kind")} = 'interaction' and cardinality(${r("medicationIds")}) = 2)
    or (${r("kind")} = 'duplicate_therapy' and cardinality(${r("medicationIds")}) >= 2)
  )
);${appKey("rules", "tenant_id", `${r("tenant")}, ${r("id")}`)}
create index if not exists ${name("rules", "tenant_idx")} on ${sql.rules} (${r("tenant")}, ${r("kind")});
${lockTable(sql.rules, { read: true })}
${readPolicy("rules", r("tenant"))}

-- An alert about a record, from the built-in rules or an external engine
-- (source). The fingerprint identifies the finding, so evaluating again updates
-- the alert instead of raising it twice and keeps a member's decision. order_ids
-- are the medication orders involved.
create table if not exists ${sql.alerts} (
  ${a("id")} uuid primary key default gen_random_uuid(),
  ${a("tenant")} ${ctx.idType} not null,
  ${a("subjectType")} text not null,
  ${a("subjectId")} text not null,
  ${a("kind")} text not null check (${a("kind")} in (${quoted(CARE_ALERT_KINDS)})),
  ${a("severity")} text not null check (${a("severity")} in (${quoted(CARE_ALERT_SEVERITIES)})),
  ${a("source")} text not null check (length(${a("source")}) between 1 and 100),
  ${a("rule")} uuid,
  ${a("orderIds")} uuid[] not null default '{}',
  ${a("message")} text not null check (length(${a("message")}) between 1 and 1000),
  ${a("details")} jsonb,
  ${a("fingerprint")} text not null check (length(${a("fingerprint")}) between 1 and 200),
  ${a("status")} text not null default 'open' check (${a("status")} in (${quoted(CARE_ALERT_STATUSES)})),
  ${a("decidedBy")} uuid,
  ${a("decidedAt")} timestamptz,
  ${a("decisionReason")} text check (${a("decisionReason")} is null or length(${a("decisionReason")}) <= 1000),
  ${a("createdAt")} timestamptz not null default now(),
  ${a("updatedAt")} timestamptz not null default now(),
  check (${a("status")} not in ('acknowledged', 'overridden') or ${a("decidedAt")} is not null)
);${appKey("alerts", "tenant_id", `${a("tenant")}, ${a("id")}`)}
create unique index if not exists ${name("alerts", "live_key")} on ${sql.alerts} (${a("tenant")}, ${a("subjectType")}, ${a("subjectId")}, ${a("fingerprint")}) where ${a("status")} <> 'resolved';
create index if not exists ${name("alerts", "subject_idx")} on ${sql.alerts} (${a("tenant")}, ${a("subjectType")}, ${a("subjectId")}, ${a("status")});
${lockTable(sql.alerts, { read: true })}
${readPolicy("alerts", a("tenant"))}
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  return `${schemaPreamble(ctx)}
-- Clinical decision support: tenant rules for dose range, duplicate therapy
-- and interactions over a record's medication orders, alerts that members
-- acknowledge or override with a reason, and a context function for external
-- engines whose alerts are stored the same way.
${tables(ctx)}${decisionSupportEvaluation(ctx)}${decisionSupportFunctions(ctx)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    { name: "save_care_rule", args: ["{id}", "jsonb"], returns: "jsonb" },
    { name: "delete_care_rule", args: ["uuid"], returns: "jsonb" },
    { name: "list_care_rules", args: ["{id}"], returns: "jsonb" },
    {
      name: "evaluate_care_rules",
      args: ["{id}", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "record_care_alerts",
      args: ["{id}", "text", "text", "text", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "care_decision_context",
      args: ["{id}", "text", "text"],
      returns: "jsonb",
    },
    { name: "list_care_alerts", args: ["{id}", "jsonb"], returns: "jsonb" },
    {
      name: "decide_care_alert",
      args: ["uuid", "text", "text"],
      returns: "jsonb",
    },
  ];
}

export const CLINICAL_DECISION_SUPPORT: BlockSqlDefinition = {
  name: "clinical-decision-support",
  scopes: ["tenant"],
  title: "Clinical decision support",
  description:
    "Tenant rules for dose range, duplicate therapy and interactions over a record's medication orders, alerts that members acknowledge or override with a reason, and a decision context for external engines whose alerts are stored the same way.",
  requires: ["memberships", "permissions", "subjects", "medications"],
  integrates: ["observations", "consents", "care-plans", "outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
