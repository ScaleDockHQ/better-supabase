import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";

import { fail, userGrant } from "../shared.ts";
import { purgeBypass } from "./ledger.ts";

/** The proof-of-delivery columns of the shipments table, for the module's names. */
export const PROOF_COLUMNS = {
  deliveredTo: "delivered_to",
  proofReference: "proof_reference",
  proofAttachment: "proof_attachment_id",
  proofRecordedAt: "proof_recorded_at",
} as const;

/** The proof columns the app may map to null. */
export const PROOF_OPTIONAL: readonly string[] = Object.keys(PROOF_COLUMNS);

export const proofContract: readonly BlockSqlContractFunction[] = [
  {
    name: "record_delivery_proof",
    args: ["uuid", "text", "text", "uuid"],
    returns: "jsonb",
  },
];

/** Adds the proof columns to a shipments table that was created before them. */
export function proofColumnsSql(ctx: BlockSqlContext, table: string): string {
  const add = (logical: string, type: string): string =>
    ctx.has("shipments", logical)
      ? `\nalter table ${table} add column if not exists ${ctx.col("shipments", logical)} ${type};`
      : "";

  return `${add("deliveredTo", "text")}${add("proofReference", "text")}${add("proofAttachment", "uuid")}${add("proofRecordedAt", "timestamptz")}`;
}

/**
 * Tracking events are evidence of when a parcel moved, so only the module's
 * functions write them and nothing edits or deletes one afterwards.
 */
export function eventsAppendOnlySql(
  ctx: BlockSqlContext,
  events: string,
): string {
  const name = ctx.fn("shipment_events_append_only");
  const tenant = ctx.colName("trackingEvents", "tenant");

  return `
-- Tracking events are append-only: a correction is a later event.
create or replace function ${name}()
returns trigger
language plpgsql
set search_path = ''
as $$
begin${purgeBypass(ctx)}
  ${fail("SHIPMENT_EVENTS_APPEND_ONLY", "tracking events can't be changed or deleted; record a later event", "55000")}
end;
$$;
revoke execute on function ${name}() from public, anon, authenticated;
drop trigger if exists ${ctx.trigger("shipment_events_append_only")} on ${events};
create trigger ${ctx.trigger("shipment_events_append_only")} before update or delete on ${events}
  for each row execute function ${name}('${tenant}');`;
}

/** The pieces `record_delivery_proof` takes from the shipments module. */
export interface ProofFunctionParts {
  readonly shipments: string;
  readonly h: (column: string) => string;
  readonly findForWrite: (arg: string) => string;
  /** SQL that is true when v_ship has not been delivered. */
  readonly notDelivered: string;
  readonly shipmentJson: (row: string) => string;
  readonly record: string;
}

/** Stores who received a delivered parcel and the carrier's proof, once. */
export function proofFunctionSql(
  ctx: BlockSqlContext,
  parts: ProofFunctionParts,
): string {
  const { shipments, h } = parts;

  if (!ctx.has("shipments", "deliveredTo")) {
    return "";
  }

  const set = (logical: string, value: string): string =>
    ctx.has("shipments", logical) ? `\n      ${h(logical)} = ${value},` : "";

  const fn = ctx.fn("record_delivery_proof");

  const recorded = ctx.has("shipments", "proofRecordedAt")
    ? `v_ship.${h("proofRecordedAt")} is not null`
    : "false";

  return `
-- Records the proof of a delivered shipment: who received it, the carrier's
-- reference and the attachment that holds the receipt. It can be set once.
create or replace function ${fn}(shipment_id uuid, delivered_to text, proof_reference text default null, attachment_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship ${shipments}%rowtype;
begin
${parts.findForWrite("record_delivery_proof.shipment_id")}
  if ${parts.notDelivered} then
    ${fail("SHIPMENT_NOT_DELIVERED", "proof can only be recorded for a delivered shipment", "55000")}
  end if;
  if record_delivery_proof.delivered_to is null or length(btrim(record_delivery_proof.delivered_to)) not between 1 and 500 then
    ${fail("SHIPMENT_PROOF_INVALID", "delivered_to needs 1 to 500 characters", "22023")}
  end if;
  if ${recorded} then
    ${fail("SHIPMENT_PROOF_RECORDED", "the proof of delivery is already recorded", "55000")}
  end if;
  update ${shipments} x set${set("deliveredTo", "btrim(record_delivery_proof.delivered_to)")}${set("proofReference", "record_delivery_proof.proof_reference")}${set("proofAttachment", "record_delivery_proof.attachment_id")}${set("proofRecordedAt", "now()")}
    ${h("updatedAt")} = now()
  where x.${h("id")} = v_ship.${h("id")}
  returning * into v_ship;
  ${parts.record}
  return ${parts.shipmentJson("v_ship")};
end;
$$;
${userGrant(`${fn}(uuid, text, text, uuid)`)}`;
}
