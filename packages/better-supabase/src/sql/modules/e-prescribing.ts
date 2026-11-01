import type { EPrescribingEvents } from "../../blocks/e-prescribing/events.ts";
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
import { prescribingFunctions } from "./e-prescribing-functions.ts";
import { prescribingSql } from "./e-prescribing-sql.ts";
import { PRESCRIPTION_STATUSES } from "./e-prescribing-values.ts";

const prescription = {
  subject: "prescriptions",
  payload: [
    "organizationId",
    "id",
    "orderId",
    "subjectType",
    "subjectId",
    "status",
  ],
} as const;

const EVENTS: BlockSqlEvents<EPrescribingEvents> = {
  "prescription.created": prescription,
  "prescription.signed": prescription,
  "prescription.sent": prescription,
  "prescription.delivery_failed": prescription,
  "prescription.dispensed": prescription,
  "prescription.cancelled": prescription,
};

const NAMES: BlockSqlNames = {
  entities: {
    prescription: {
      table: "prescriptions",
      singular: "prescription",
      primary: true,
    },
  },
  events: EVENTS,
  hooks: ["before_prescription_sign", "after_prescription_sign"],
  options: [],
  tables: {
    prescriptions: {
      name: "prescriptions",
      app: {},
      lifecycle: { tenant: "tenant", user: "prescriber", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        order: "order_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        prescriber: "prescriber_id",
        prescriberName: "prescriber_name",
        status: "status",
        snapshot: "snapshot",
        signedBy: "signed_by",
        signedAt: "signed_at",
        gateway: "gateway",
        gatewayReference: "gateway_reference",
        sentAt: "sent_at",
        deliveryError: "delivery_error",
        dispensedAt: "dispensed_at",
        cancelledAt: "cancelled_at",
        cancelReason: "cancel_reason",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
  },
};

const quoted = (values: readonly string[]): string =>
  values.map((value) => `'${value}'`).join(", ");

function tables(ctx: BlockSqlContext): string {
  const sql = prescribingSql(ctx);
  const { p } = sql;
  const orders = sql.medications.table("orders");
  const o = (column: string): string => sql.medications.col("orders", column);

  const name = (suffix: string): string =>
    sqlIdent(`${ctx.tableName("prescriptions").name}_${suffix}`);

  const appKey = ctx.owns("prescriptions")
    ? ""
    : `\ncreate unique index if not exists ${sqlIdent(`bsb_${ctx.tableName("prescriptions").name}_tenant_id_key`)} on ${sql.prescriptions} (${p("tenant")}, ${p("id")});`;

  const readPolicy = renderPolicy(
    makePolicy({
      table: sql.prescriptions,
      name: ctx.owns("prescriptions")
        ? name("read")
        : sqlIdent(`bsb_${ctx.tableName("prescriptions").name}_read`),
      command: "select",
      roles: ["authenticated"],
      using: ctx.scope.check(p("tenant"), sql.read),
    }),
    { drop: true, target: sql.prescriptions },
  );

  return `
-- A prescription of one medication order. It starts as a draft by the prescriber,
-- the prescriber signs it (snapshot freezes the order), a gateway delivers it
-- and the pharmacy dispenses it. Only the functions change it; a signed
-- prescription always has a signer and a time.
create table if not exists ${sql.prescriptions} (
  ${p("id")} uuid primary key default gen_random_uuid(),
  ${p("tenant")} ${ctx.idType} not null,
  ${p("order")} uuid not null,
  ${p("subjectType")} text not null,
  ${p("subjectId")} text not null,
  ${p("prescriber")} uuid not null,
  ${p("prescriberName")} text check (${p("prescriberName")} is null or length(${p("prescriberName")}) <= 300),
  ${p("status")} text not null default 'draft' check (${p("status")} in (${quoted(PRESCRIPTION_STATUSES)})),
  ${p("snapshot")} jsonb,
  ${p("signedBy")} uuid,
  ${p("signedAt")} timestamptz,
  ${p("gateway")} text check (${p("gateway")} is null or length(${p("gateway")}) between 1 and 100),
  ${p("gatewayReference")} text check (${p("gatewayReference")} is null or length(${p("gatewayReference")}) <= 200),
  ${p("sentAt")} timestamptz,
  ${p("deliveryError")} text check (${p("deliveryError")} is null or length(${p("deliveryError")}) <= 1000),
  ${p("dispensedAt")} timestamptz,
  ${p("cancelledAt")} timestamptz,
  ${p("cancelReason")} text check (${p("cancelReason")} is null or length(${p("cancelReason")}) <= 1000),
  ${p("createdAt")} timestamptz not null default now(),
  ${p("updatedAt")} timestamptz not null default now(),
  check (${p("status")} in ('draft', 'cancelled') or (${p("signedBy")} is not null and ${p("signedAt")} is not null and ${p("snapshot")} is not null)),
  check (${p("signedBy")} is null or ${p("signedBy")} = ${p("prescriber")}),
  check (${p("status")} not in ('sent', 'dispensed') or (${p("sentAt")} is not null and ${p("gateway")} is not null)),
  check (${p("status")} <> 'dispensed' or ${p("dispensedAt")} is not null),
  check (${p("status")} <> 'cancelled' or ${p("cancelledAt")} is not null),
  foreign key (${p("tenant")}, ${p("order")}) references ${orders} (${o("tenant")}, ${o("id")})
);${appKey}
create unique index if not exists ${name("live_order_key")} on ${sql.prescriptions} (${p("tenant")}, ${p("order")}) where ${p("status")} <> 'cancelled';
create index if not exists ${name("order_idx")} on ${sql.prescriptions} (${p("tenant")}, ${p("order")});
create index if not exists ${name("subject_idx")} on ${sql.prescriptions} (${p("tenant")}, ${p("subjectType")}, ${p("subjectId")});
create index if not exists ${name("status_idx")} on ${sql.prescriptions} (${p("tenant")}, ${p("status")});
${lockTable(sql.prescriptions, { read: true })}
${readPolicy}
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  return `${schemaPreamble(ctx)}
-- E-prescribing: prescriptions over medication orders with states draft, signed,
-- sent, dispensed and cancelled, a signature only the prescriber can give, and
-- delivery recorded for a gateway that plugs in through the PrescriptionGateway
-- port.
${tables(ctx)}${prescribingFunctions(ctx)}`;
}

function contract(): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "create_prescription",
      args: ["{id}", "uuid", "jsonb"],
      returns: "jsonb",
    },
    { name: "sign_prescription", args: ["uuid"], returns: "jsonb" },
    {
      name: "record_prescription_delivery",
      args: ["uuid", "text", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "record_prescription_dispense",
      args: ["uuid", "timestamptz"],
      returns: "jsonb",
    },
    { name: "cancel_prescription", args: ["uuid", "text"], returns: "jsonb" },
    { name: "get_prescription", args: ["uuid"], returns: "jsonb" },
    { name: "list_prescriptions", args: ["{id}", "jsonb"], returns: "jsonb" },
  ];
}

export const E_PRESCRIBING: BlockSqlDefinition = {
  name: "e-prescribing",
  scopes: ["tenant"],
  title: "E-prescribing",
  description:
    "Prescriptions over medication orders with the states draft, signed, sent, dispensed and cancelled, a signature only the prescriber can give, and delivery through a PrescriptionGateway port that carries a FHIR R4 MedicationRequest.",
  requires: ["memberships", "permissions", "subjects", "medications"],
  integrates: ["outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
