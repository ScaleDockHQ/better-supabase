import type { ShipmentsEvents } from "../../blocks/shipments/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
} from "../context.ts";

import { filterAny, filterSet } from "../list-template.ts";
import { fail, userGrant } from "../shared.ts";

/** What `archiveFunctions` takes from the shipments module's builders. */
export interface ArchiveParts {
  readonly ctx: BlockSqlContext;
  readonly shipments: string;
  readonly h: (column: string) => string;
  readonly fn: (name: string) => string;
  readonly st: (
    row: string,
    labels: readonly string[],
    negate?: boolean,
  ) => string;
  readonly findForWrite: (arg: string) => string;
  readonly shipmentJson: (row: string) => string;
  readonly base: (row: string) => string;
  readonly subject: (row: string) => string;
  readonly audited: (
    row: string,
    summary: string,
  ) => Parameters<BlockSqlContext["record"]>[0]["audit"];
}

/**
 * `archive_shipment` and `restore_shipment`, when the shipments table has the
 * `archivedAt` column.
 */
export function archiveFunctions(p: ArchiveParts): string {
  const {
    ctx,
    shipments,
    h,
    fn,
    st,
    findForWrite,
    shipmentJson,
    base,
    subject,
    audited,
  } = p;

  return ctx.has("shipments", "archivedAt")
    ? ["archive", "restore"]
        .map((verb) => {
          const past = verb === "archive" ? "archived" : "restored";

          return `
-- ${verb === "archive" ? "Archives a shipment that ended (delivered, returned or cancelled): it leaves the lists and keeps its packages, lines and tracking." : "Restores an archived shipment to the lists."}
create or replace function ${fn(`${verb}_shipment`)}(shipment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_ship ${shipments}%rowtype;
begin
${findForWrite(`${verb}_shipment.shipment_id`)}
  if v_ship.${h("archivedAt")} ${verb === "archive" ? "is not null" : "is null"} then
    return ${shipmentJson("v_ship")};
  end if;${
    verb === "archive"
      ? `
  if ${st("v_ship", ["delivered", "returned", "cancelled"], true)} then
    ${fail("SHIPMENT_ACTIVE", "only a delivered, returned or cancelled shipment is archived", "55000")}
  end if;`
      : ""
  }
  update ${shipments} x set
    ${h("archivedAt")} = ${verb === "archive" ? "now()" : "null"},
    ${h("updatedAt")} = now()
  where x.${h("id")} = v_ship.${h("id")}
  returning * into v_ship;
  ${ctx.record({
    type: `shipment.${past}`,
    payload: `jsonb_build_object(${base("v_ship")})`,
    subject: subject("v_ship"),
    tenant: `v_ship.${h("tenant")}`,
    audit: audited("v_ship", `${past} shipment`),
  })}
  return ${shipmentJson("v_ship")};
end;
$$;
${userGrant(`${fn(`${verb}_shipment`)}(uuid)`)}
`;
        })
        .join("")
    : "";
}

/** The contract entries of the archive functions. */
export const archiveContract = (
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] =>
  ctx.has("shipments", "archivedAt")
    ? [
        { name: "archive_shipment", args: ["uuid"], returns: "jsonb" },
        { name: "restore_shipment", args: ["uuid"], returns: "jsonb" },
      ]
    : [];

/**
 * The `list_shipments` predicate that hides archived shipments, and with the
 * `archived` filter lists them.
 */
export const archiveFilter = (
  ctx: BlockSqlContext,
  h: (column: string) => string,
): readonly string[] =>
  ctx.has("shipments", "archivedAt")
    ? [
        `(case when ${filterSet("archived")} then ${filterAny("archived", `(x.${h("archivedAt")} is not null)::text`)} else x.${h("archivedAt")} is null end)`,
      ]
    : [];

/** The `shipment.archived` and `shipment.restored` events. */
export const ARCHIVE_EVENTS: Pick<
  BlockSqlEvents<ShipmentsEvents>,
  "shipment.archived" | "shipment.restored"
> = {
  "shipment.archived": {
    subject: "shipments",
    payload: ["organizationId", "id"],
  },
  "shipment.restored": {
    subject: "shipments",
    payload: ["organizationId", "id"],
  },
};
