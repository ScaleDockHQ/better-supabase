import type { LeasesEvents } from "../../blocks/leases/events.ts";
import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleEvents,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { lockTable, schemaPreamble } from "../shared.ts";
import { moveSubjectRows, subjectMergeHandler } from "../subject-merge-sql.ts";
import { registeredSubjects } from "../subject-registry.ts";
import { moduleOperations } from "./access-model.ts";
import { leasesFunctions } from "./leases-functions.ts";

const LEASE_PAYLOAD = [
  "organizationId",
  "id",
  "unitId",
  "partyType",
  "partyId",
  "status",
  "startsOn",
  "endsOn",
  "rent",
  "currency",
] as const;

const CHARGE_PAYLOAD = [
  "organizationId",
  "id",
  "leaseId",
  "periodStart",
  "periodEnd",
  "amount",
  "currency",
  "transactionId",
] as const;

const MAINTENANCE_PAYLOAD = [
  "organizationId",
  "id",
  "unitId",
  "leaseId",
  "priority",
  "status",
] as const;

const EVENTS: ModuleEvents<LeasesEvents> = {
  "lease.created": { subject: "leases", payload: LEASE_PAYLOAD },
  "lease.activated": { subject: "leases", payload: LEASE_PAYLOAD },
  "lease.renewed": { subject: "leases", payload: LEASE_PAYLOAD },
  "lease.terminated": { subject: "leases", payload: LEASE_PAYLOAD },
  "lease.charged": { subject: "lease-charges", payload: CHARGE_PAYLOAD },
  "lease.paid": {
    subject: "leases",
    payload: ["organizationId", "id", "transactionId", "amount", "currency"],
  },
  "maintenance_request.filed": {
    subject: "maintenance-requests",
    payload: MAINTENANCE_PAYLOAD,
  },
  "maintenance_request.updated": {
    subject: "maintenance-requests",
    payload: MAINTENANCE_PAYLOAD,
  },
};

const NAMES: ModuleNames = {
  entities: {
    lease: {
      table: "leases",
      singular: "lease",
      primary: true,
      subject: {
        title: "title",
        permissions: { read: "read", write: "manage" },
      },
    },
    maintenance_request: {
      table: "maintenance",
      singular: "maintenance_request",
      subject: {
        title: "title",
        permissions: { read: "read", write: "maintain" },
      },
    },
  },
  events: EVENTS,
  options: [],
  tables: {
    leases: {
      name: "leases",
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        unit: "unit_id",
        partyType: "party_type",
        partyId: "party_id",
        title: "title",
        status: "status",
        startsOn: "starts_on",
        endsOn: "ends_on",
        rent: "rent",
        currency: "currency",
        frequency: "frequency",
        deposit: "deposit",
        depositHold: "deposit_hold_id",
        renewedAt: "renewed_at",
        terminatedOn: "terminated_on",
        terminationReason: "termination_reason",
        metadata: "metadata",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    charges: {
      name: "lease_charges",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        lease: "lease_id",
        periodStart: "period_start",
        periodEnd: "period_end",
        amount: "amount",
        currency: "currency",
        transaction: "transaction_id",
        createdAt: "created_at",
      },
    },
    maintenance: {
      name: "maintenance_requests",
      lifecycle: { tenant: "tenant", user: "reportedBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        unit: "unit_id",
        lease: "lease_id",
        title: "title",
        description: "description",
        priority: "priority",
        status: "status",
        reportedBy: "reported_by",
        assignee: "assignee_id",
        resolvedAt: "resolved_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
  },
};

function tables(ctx: ModuleContext): string {
  if (!ctx.manages) {
    return "";
  }

  const assets = ctx.of("assets");
  const leases = ctx.table("leases");
  const charges = ctx.table("charges");
  const maintenance = ctx.table("maintenance");
  const l = (column: string): string => ctx.col("leases", column);
  const c = (column: string): string => ctx.col("charges", column);
  const m = (column: string): string => ctx.col("maintenance", column);
  const ops = moduleOperations("leases");
  const read = ctx.permission("read", ops.read);
  const unit = `${assets.table("assets")} (${assets.col("assets", "id")})`;

  const index = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  return `
create table if not exists ${leases} (
  ${l("id")} uuid primary key default gen_random_uuid(),
  ${l("tenant")} ${ctx.idType} not null,
  ${l("unit")} uuid not null references ${unit} on delete restrict,
  -- The party renting the unit: a registered subject such as a contact.
  ${l("partyType")} text not null,
  ${l("partyId")} text not null,
  ${l("title")} text not null check (length(${l("title")}) between 1 and 200),
  ${l("status")} text not null default 'draft' check (${l("status")} in ('draft', 'active', 'ended', 'terminated')),
  ${l("startsOn")} date not null,
  -- Null runs the lease until it is terminated.
  ${l("endsOn")} date,
  -- Minor units of currency per period (ADR 0037).
  ${l("rent")} bigint not null check (${l("rent")} > 0),
  ${l("currency")} char(3) not null check (${l("currency")} ~ '^[A-Z]{3}$'),
  ${l("frequency")} text not null default 'monthly' check (${l("frequency")} in ('weekly', 'monthly', 'quarterly', 'yearly')),
  ${l("deposit")} bigint not null default 0 check (${l("deposit")} >= 0),
  -- The ledger hold that keeps the deposit aside while the lease runs.
  ${l("depositHold")} uuid,
  ${l("renewedAt")} timestamptz,
  ${l("terminatedOn")} date,
  ${l("terminationReason")} text check (${l("terminationReason")} is null or length(${l("terminationReason")}) <= 2000),
  ${l("metadata")} jsonb not null default '{}'::jsonb,
  ${l("createdBy")} uuid,
  ${l("createdAt")} timestamptz not null default now(),
  ${l("updatedAt")} timestamptz not null default now(),
  check (${l("endsOn")} is null or ${l("endsOn")} > ${l("startsOn")})
);
create index if not exists ${index("leases", "tenant_idx")} on ${leases} (${l("tenant")}, ${l("status")}, ${l("startsOn")} desc);
create index if not exists ${index("leases", "unit_idx")} on ${leases} (${l("unit")});
create index if not exists ${index("leases", "party_idx")} on ${leases} (${l("tenant")}, ${l("partyType")}, ${l("partyId")});
create index if not exists ${index("leases", "deposit_hold_idx")} on ${leases} (${l("depositHold")}) where ${l("depositHold")} is not null;
${lockTable(leases, { read: true })}
drop policy if exists ${index("leases", "read")} on ${leases};
create policy ${index("leases", "read")} on ${leases} for select to authenticated
  using (${ctx.scope.check(l("tenant"), read)});

-- One row per rent period posted to the ledger, so each period posts once.
create table if not exists ${charges} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${ctx.idType} not null,
  ${c("lease")} uuid not null references ${leases} (${l("id")}) on delete restrict,
  ${c("periodStart")} date not null,
  ${c("periodEnd")} date not null,
  ${c("amount")} bigint not null check (${c("amount")} > 0),
  ${c("currency")} char(3) not null,
  ${c("transaction")} uuid not null,
  ${c("createdAt")} timestamptz not null default now(),
  unique (${c("lease")}, ${c("periodStart")}),
  check (${c("periodEnd")} > ${c("periodStart")})
);
create index if not exists ${index("charges", "tenant_idx")} on ${charges} (${c("tenant")}, ${c("periodStart")} desc);
create index if not exists ${index("charges", "transaction_idx")} on ${charges} (${c("transaction")});
${lockTable(charges, { read: true })}
drop policy if exists ${index("charges", "read")} on ${charges};
create policy ${index("charges", "read")} on ${charges} for select to authenticated
  using (${ctx.scope.check(c("tenant"), read)});

create table if not exists ${maintenance} (
  ${m("id")} uuid primary key default gen_random_uuid(),
  ${m("tenant")} ${ctx.idType} not null,
  ${m("unit")} uuid not null references ${unit} on delete cascade,
  ${m("lease")} uuid references ${leases} (${l("id")}) on delete set null,
  ${m("title")} text not null check (length(${m("title")}) between 1 and 200),
  ${m("description")} text check (${m("description")} is null or length(${m("description")}) <= 5000),
  ${m("priority")} text not null default 'normal' check (${m("priority")} in ('low', 'normal', 'high', 'urgent')),
  ${m("status")} text not null default 'open' check (${m("status")} in ('open', 'in_progress', 'resolved', 'cancelled')),
  ${m("reportedBy")} uuid,
  ${m("assignee")} uuid,
  ${m("resolvedAt")} timestamptz,
  ${m("createdAt")} timestamptz not null default now(),
  ${m("updatedAt")} timestamptz not null default now()
);
create index if not exists ${index("maintenance", "tenant_idx")} on ${maintenance} (${m("tenant")}, ${m("status")}, ${m("createdAt")} desc);
create index if not exists ${index("maintenance", "unit_idx")} on ${maintenance} (${m("unit")});
create index if not exists ${index("maintenance", "tenancy_idx")} on ${maintenance} (${m("lease")}) where ${m("lease")} is not null;
${lockTable(maintenance, { read: true })}
drop policy if exists ${index("maintenance", "read")} on ${maintenance};
create policy ${index("maintenance", "read")} on ${maintenance} for select to authenticated
  using (${m("reportedBy")} = (select auth.uid()) or ${ctx.scope.check(m("tenant"), read)});
`;
}

/** Moves the leases of a merged party to the record it merged into. */
function partyMerges(ctx: ModuleContext): string {
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
        table: ctx.table("leases"),
        type: ctx.col("leases", "partyType"),
        id: ctx.col("leases", "partyId"),
      },
      "v_type",
    ),
  );
}

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  for (const needed of ["assets", "ledger"]) {
    if (ctx.of(needed).mode === "custom") {
      throw new TypeError(
        `blocks.leases needs the ${needed} tables; ${needed} can't be in custom mode`,
      );
    }
  }

  return `${schemaPreamble(ctx)}
-- Leases: units (assets) let to parties, rent posted on the ledger once per
-- period, deposits held through ledger holds, and maintenance requests.
${tables(ctx)}${leasesFunctions(ctx)}${partyMerges(ctx)}`;
}

function contract(_ctx: ModuleContext): readonly ModuleContractFunction[] {
  return [
    {
      name: "create_lease",
      args: [
        "{id}",
        "uuid",
        "text",
        "text",
        "date",
        "bigint",
        "text",
        "text",
        "date",
        "bigint",
        "text",
        "jsonb",
      ],
      returns: "jsonb",
    },
    { name: "activate_lease", args: ["uuid"], returns: "jsonb" },
    { name: "renew_lease", args: ["uuid", "date", "bigint"], returns: "jsonb" },
    {
      name: "terminate_lease",
      args: ["uuid", "date", "text", "bigint"],
      returns: "jsonb",
    },
    { name: "get_lease", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_leases",
      args: ["{id}", "text", "uuid", "text", "text", "integer"],
      returns: "jsonb",
    },
    {
      name: "post_due_rent",
      args: ["{id}", "date", "integer"],
      returns: "integer",
    },
    {
      name: "record_rent_payment",
      args: ["uuid", "bigint", "timestamptz", "text"],
      returns: "jsonb",
    },
    { name: "list_lease_charges", args: ["uuid", "integer"], returns: "jsonb" },
    {
      name: "file_maintenance_request",
      args: ["{id}", "uuid", "text", "text", "text", "uuid"],
      returns: "jsonb",
    },
    {
      name: "update_maintenance_request",
      args: ["uuid", "text", "text", "uuid"],
      returns: "jsonb",
    },
    {
      name: "list_maintenance_requests",
      args: ["{id}", "uuid", "uuid", "text", "integer"],
      returns: "jsonb",
    },
  ];
}

export const LEASES: ModuleDefinition = {
  name: "leases",
  scopes: ["tenant"],
  title: "Leases",
  description:
    "Leases of units (assets) to parties with rent in bigint minor units and a frequency, rent charges posted on the ledger once per period, deposits held through ledger holds, renewals, terminations and maintenance requests on the unit.",
  requires: ["tenant", "access", "subjects", "assets", "ledger"],
  integrates: ["outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
