import type { ContractsEvents } from "../../blocks/contracts/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import {
  addExtraColumns,
  extraFieldsArg,
  lockTable,
  schemaPreamble,
} from "../shared.ts";
import { moveSubjectRows, subjectMergeHandler } from "../subject-merge-sql.ts";
import { registeredSubjects } from "../subject-registry.ts";
import { contractsFunctions } from "./contracts-functions.ts";
import { CONTRACT_RESERVED, CONTRACT_STATUSES } from "./contracts-shared.ts";
import { moduleOperations } from "./permissions-model.ts";

const CONTRACT_PAYLOAD = [
  "organizationId",
  "contractId",
  "title",
  "status",
] as const;

const OBLIGATION_PAYLOAD = [
  "organizationId",
  "obligationId",
  "contractId",
  "status",
] as const;

const EVENTS: BlockSqlEvents<ContractsEvents> = {
  "contract.created": { subject: "contracts", payload: CONTRACT_PAYLOAD },
  "contract.updated": { subject: "contracts", payload: CONTRACT_PAYLOAD },
  "contract.status_changed": {
    subject: "contracts",
    payload: ["organizationId", "contractId", "status", "previousStatus"],
  },
  "contract.renewed": {
    subject: "contracts",
    payload: ["organizationId", "contractId", "endsOn", "renewedCount"],
  },
  "obligation.saved": { subject: "obligations", payload: OBLIGATION_PAYLOAD },
  "obligation.status_changed": {
    subject: "obligations",
    payload: OBLIGATION_PAYLOAD,
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    contract: {
      table: "contracts",
      singular: "contract",
      primary: true,
      subject: {
        title: "title",
        permissions: { read: "read", write: "write" },
      },
    },
    obligation: { table: "obligations", singular: "obligation" },
  },
  events: EVENTS,
  options: ["reminderDays", "extraColumns"],
  tables: {
    contracts: {
      name: "contracts",
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        title: "title",
        description: "description",
        counterpartyType: "counterparty_type",
        counterpartyId: "counterparty_id",
        owner: "owner_id",
        status: "status",
        value: "value",
        currency: "currency",
        startsOn: "starts_on",
        endsOn: "ends_on",
        autoRenew: "auto_renew",
        renewalMonths: "renewal_months",
        noticeDays: "notice_days",
        renewedCount: "renewed_count",
        signatureRequest: "signature_request_id",
        signedAt: "signed_at",
        terminatedAt: "terminated_at",
        terminationReason: "termination_reason",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    obligations: {
      name: "contract_obligations",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        contract: "contract_id",
        title: "title",
        description: "description",
        dueOn: "due_on",
        owner: "owner_id",
        status: "status",
        completedAt: "completed_at",
        completedBy: "completed_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
  },
};

function tables(ctx: BlockSqlContext): string {
  const contracts = ctx.table("contracts");
  const obligations = ctx.table("obligations");
  const c = (column: string): string => ctx.col("contracts", column);
  const o = (column: string): string => ctx.col("obligations", column);
  const signatures = ctx.of("signatures");
  const extras = ctx.extraColumns("contracts", CONTRACT_RESERVED);
  const read = ctx.permission("read", moduleOperations("contracts").read);

  const name = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  const statuses = CONTRACT_STATUSES.map((status) => `'${status}'`).join(", ");

  return `
create table if not exists ${contracts} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("title")} text not null check (length(${c("title")}) between 1 and 200),
  ${c("description")} text check (${c("description")} is null or length(${c("description")}) <= 10000),
  -- The other party: a registered subject (a company or person of the parties block, say).
  ${c("counterpartyType")} text,
  ${c("counterpartyId")} text,
  ${c("owner")} uuid,
  ${c("status")} text not null default 'draft' check (${c("status")} in (${statuses})),
  -- The contract value in minor units of currency.
  ${c("value")} bigint check (${c("value")} is null or ${c("value")} >= 0),
  ${c("currency")} text check (${c("currency")} is null or ${c("currency")} ~ '^[A-Z]{3}$'),
  ${c("startsOn")} date,
  ${c("endsOn")} date,
  ${c("autoRenew")} boolean not null default false,
  -- How far an auto-renewal moves ends_on.
  ${c("renewalMonths")} integer not null default 12 check (${c("renewalMonths")} between 1 and 120),
  -- How many days before ends_on notice of termination is due.
  ${c("noticeDays")} integer not null default 30 check (${c("noticeDays")} between 0 and 3650),
  ${c("renewedCount")} integer not null default 0,
  ${c("signatureRequest")} uuid${signatures.manages ? ` references ${signatures.table("requests")} (${signatures.col("requests", "id")}) on delete set null` : ""},
  ${c("signedAt")} timestamptz,
  ${c("terminatedAt")} timestamptz,
  ${c("terminationReason")} text check (${c("terminationReason")} is null or length(${c("terminationReason")}) <= 2000),
  ${c("createdBy")} uuid,
  ${c("createdAt")} timestamptz not null default now(),
  ${c("updatedAt")} timestamptz not null default now(),
  check ((${c("counterpartyType")} is null) = (${c("counterpartyId")} is null)),
  check ((${c("value")} is null) = (${c("currency")} is null)),
  check (${c("endsOn")} is null or ${c("startsOn")} is null or ${c("endsOn")} >= ${c("startsOn")}),
  unique (${c("tenant")}, ${c("id")})
);${addExtraColumns(contracts, extras)}
create index if not exists ${name("contracts", "status_idx")} on ${contracts} (${c("tenant")}, ${c("status")}, ${c("endsOn")});
create index if not exists ${name("contracts", "counterparty_idx")} on ${contracts} (${c("tenant")}, ${c("counterpartyType")}, ${c("counterpartyId")}) where ${c("counterpartyType")} is not null;
create index if not exists ${name("contracts", "owner_idx")} on ${contracts} (${c("tenant")}, ${c("owner")}) where ${c("owner")} is not null;
create index if not exists ${name("contracts", "signature_idx")} on ${contracts} (${c("signatureRequest")}) where ${c("signatureRequest")} is not null;
${lockTable(contracts, { read: true })}
drop policy if exists ${name("contracts", "read")} on ${contracts};
create policy ${name("contracts", "read")} on ${contracts} for select to authenticated
  using (${c("owner")} = (select auth.uid()) or ${ctx.scope.check(c("tenant"), read)});

create table if not exists ${obligations} (
  ${o("id")} uuid primary key default gen_random_uuid(),
  ${o("tenant")} ${ctx.idType} not null,
  ${o("contract")} uuid not null,
  ${o("title")} text not null check (length(${o("title")}) between 1 and 200),
  ${o("description")} text check (${o("description")} is null or length(${o("description")}) <= 4000),
  ${o("dueOn")} date,
  ${o("owner")} uuid,
  ${o("status")} text not null default 'open' check (${o("status")} in ('open', 'done', 'waived')),
  ${o("completedAt")} timestamptz,
  ${o("completedBy")} uuid,
  ${o("createdAt")} timestamptz not null default now(),
  ${o("updatedAt")} timestamptz not null default now(),
  foreign key (${o("tenant")}, ${o("contract")}) references ${contracts} (${c("tenant")}, ${c("id")}) on delete cascade
);
create index if not exists ${name("obligations", "parent_idx")} on ${obligations} (${o("tenant")}, ${o("contract")}, ${o("dueOn")});
create index if not exists ${name("obligations", "owner_idx")} on ${obligations} (${o("tenant")}, ${o("owner")}, ${o("dueOn")}) where ${o("owner")} is not null;
create index if not exists ${name("obligations", "due_idx")} on ${obligations} (${o("tenant")}, ${o("dueOn")}) where ${o("status")} = 'open';
${lockTable(obligations, { read: true })}
drop policy if exists ${name("obligations", "read")} on ${obligations};
create policy ${name("obligations", "read")} on ${obligations} for select to authenticated
  using (${o("owner")} = (select auth.uid()) or ${ctx.scope.check(o("tenant"), read)});
`;
}

/** Moves the contracts of a merged counterparty to the record it merged into. */
function counterpartyMerges(ctx: BlockSqlContext): string {
  const subjects = registeredSubjects(ctx.subjects, ctx.naming).map(
    (subject) =>
      [
        subject.type,
        { table: `${subject.schema}.${subject.table}`, extra: {} },
      ] as const,
  );

  return subjectMergeHandler(
    ctx,
    subjects,
    moveSubjectRows(
      {
        table: ctx.table("contracts"),
        type: ctx.col("contracts", "counterpartyType"),
        id: ctx.col("contracts", "counterpartyId"),
      },
      "v_type",
    ),
  );
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  for (const needed of ["signatures", "versions", "reminders"]) {
    if (ctx.of(needed).mode === "custom") {
      throw new TypeError(
        `blocks.contracts needs the ${needed} tables; ${needed} can't be in custom mode`,
      );
    }
  }

  return `${schemaPreamble(ctx)}
-- Contracts: a lifecycle from draft to signed, renewal terms with reminders
-- before the notice deadline, and obligations with due dates and owners.
${tables(ctx)}${contractsFunctions(ctx)}${counterpartyMerges(ctx)}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  const extra = extraFieldsArg(
    ctx.extraColumns("contracts", CONTRACT_RESERVED),
  ).contract;

  return [
    {
      name: "create_contract",
      args: ["{id}", "jsonb", ...extra],
      returns: "jsonb",
    },
    {
      name: "update_contract",
      args: ["uuid", "jsonb", ...extra],
      returns: "jsonb",
    },
    {
      name: "transition_contract",
      args: ["uuid", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "send_contract_for_signature",
      args: ["uuid", "uuid[]", "text", "text"],
      returns: "jsonb",
    },
    { name: "get_contract", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_contracts",
      args: [
        "{id}",
        "text",
        "text",
        "text",
        "uuid",
        "date",
        "timestamptz",
        "integer",
      ],
      returns: "jsonb",
    },
    {
      name: "save_obligation",
      args: ["uuid", "text", "date", "uuid", "text", "uuid"],
      returns: "jsonb",
    },
    { name: "set_obligation_status", args: ["uuid", "text"], returns: "jsonb" },
    { name: "delete_obligation", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_obligations",
      args: ["{id}", "uuid", "uuid", "boolean", "date", "integer"],
      returns: "jsonb",
    },
    { name: "run_contract_renewals", args: ["date"], returns: "jsonb" },
  ];
}

export const CONTRACTS: BlockSqlDefinition = {
  internal: [
    "contract_apply_status",
    "contract_schedule_renewal",
    "contract_signature_settled",
  ],
  name: "contracts",
  scopes: ["tenant"],
  title: "Contracts",
  description:
    "Contracts with counterparties from draft through review and signature to active, expired or terminated, built on signatures, versions and reminders. Values are bigint minor units; renewal terms (auto-renew, renewal period, notice days) schedule a reminder before the notice deadline; obligations carry due dates and owners.",
  requires: [
    "memberships",
    "permissions",
    "subjects",
    "versions",
    "signatures",
    "reminders",
  ],
  integrates: ["outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
