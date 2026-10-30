import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlNames,
} from "../context.ts";
import type { ApprovalContribution } from "../contributions.ts";
import type { InventoryNames } from "./inventory-stock.ts";

import { sqlString } from "../../core/template.ts";
import { fail, userGrant } from "../shared.ts";
import { policyOf, policySnapshot } from "./approvals-policies.ts";
import { DEFAULT_INSPECTION_KINDS } from "./inspections-values.ts";
import {
  linesCheck,
  linesVariantCheck,
  UNIT_COST,
} from "./inventory-purchase-lines.ts";
import { columns, guard, locationsOf } from "./inventory-stock.ts";
import { QUANTITY } from "./inventory-tracking.ts";
import { linked } from "./manufacturing-sql.ts";
import { asService } from "./orders-shared.ts";
import { OPERATIONS } from "./permissions-model.ts";

const tenantExport = { tenant: "tenant", export: true } as const;

/** Purchase requisitions and goods receipts, next to purchase orders. */
export const PROCUREMENT_TABLES: BlockSqlNames["tables"] = {
  requisitions: {
    name: "purchase_requisitions",
    app: {},
    lifecycle: tenantExport,
    optionalTable: true,
    columns: {
      id: "id",
      tenant: "tenant_id",
      location: "location_id",
      supplierType: "supplier_type",
      supplierId: "supplier_id",
      currency: "currency",
      status: "status",
      reason: "reason",
      requestedBy: "requested_by",
      decidedBy: "decided_by",
      decidedAt: "decided_at",
      approval: "approval_id",
      purchaseOrder: "purchase_order_id",
      createdAt: "created_at",
      updatedAt: "updated_at",
    },
  },
  requisitionLines: {
    name: "purchase_requisition_lines",
    app: {},
    lifecycle: tenantExport,
    optionalTable: true,
    columns: {
      id: "id",
      tenant: "tenant_id",
      requisition: "requisition_id",
      variant: "variant_id",
      quantity: "quantity",
      unitCost: "unit_cost",
    },
  },
  receipts: {
    name: "inventory_receipts",
    app: {},
    lifecycle: tenantExport,
    optionalTable: true,
    columns: {
      id: "id",
      tenant: "tenant_id",
      purchaseOrder: "purchase_order_id",
      location: "location_id",
      inspection: "inspection_id",
      receivedBy: "received_by",
      receivedAt: "received_at",
    },
  },
  receiptLines: {
    name: "inventory_receipt_lines",
    app: {},
    lifecycle: tenantExport,
    optionalTable: true,
    columns: {
      id: "id",
      tenant: "tenant_id",
      receipt: "receipt_id",
      orderLine: "purchase_order_line_id",
      variant: "variant_id",
      quantity: "quantity",
      unitCost: "unit_cost",
      detail: "detail",
    },
  },
};

export const PROCUREMENT_ENTITIES: BlockSqlNames["entities"] = {
  purchase_requisition: {
    table: "requisitions",
    singular: "purchase_requisition",
  },
  inventory_receipt: { table: "receipts", singular: "inventory_receipt" },
};

const hasOrders = (ctx: BlockSqlContext): boolean =>
  ctx.hasTable("purchaseOrders") && ctx.hasTable("purchaseOrderLines");

/** Whether the block keeps requisitions. */
export const hasRequisitions = (ctx: BlockSqlContext): boolean =>
  hasOrders(ctx) &&
  ctx.hasTable("requisitions") &&
  ctx.hasTable("requisitionLines");

/** Whether receiving a purchase order writes a receipt. */
export const hasReceipts = (ctx: BlockSqlContext): boolean =>
  hasOrders(ctx) && ctx.hasTable("receipts") && ctx.hasTable("receiptLines");

/**
 * `options.receiptInspection`: the inspection kind a receipt opens, checked
 * against the kinds inspections allows. Undefined when unset.
 */
export function receiptInspection(ctx: BlockSqlContext): string | undefined {
  const kind = ctx.option("receiptInspection");

  if (kind === undefined) {
    return undefined;
  }

  const inspections = linked(ctx, "inspections");

  if (typeof kind !== "string" || inspections === undefined) {
    throw new TypeError(
      "blocks.inventory.options.receiptInspection needs the inspections block and an inspection kind",
    );
  }

  if (!inspections.list("kinds", DEFAULT_INSPECTION_KINDS).includes(kind)) {
    throw new TypeError(
      `blocks.inventory.options.receiptInspection must be one of blocks.inspections.options.kinds, not "${kind}"`,
    );
  }

  return kind;
}

/** The requisition and receipt tables, in `tables()` of inventory. */
export function procurementTables(
  ctx: BlockSqlContext,
  read: (table: string) => string,
  lock: (table: string) => string,
  variants: string,
  location: string,
): string {
  const t = (name: string): string => ctx.table(name);

  const index = (name: string, table: string, cols: string): string =>
    `create index if not exists ${ctx.naming.rename(name)} on ${t(table)} (${cols});`;

  const po = columns(ctx, "purchaseOrders");
  const pl = columns(ctx, "purchaseOrderLines");
  const rq = columns(ctx, "requisitions");
  const rl = columns(ctx, "requisitionLines");
  const rc = columns(ctx, "receipts");
  const cl = columns(ctx, "receiptLines");

  const requisitions = hasRequisitions(ctx)
    ? `
create table if not exists ${t("requisitions")} (
  ${rq("id")} uuid primary key default gen_random_uuid(),
  ${rq("tenant")} ${ctx.idType} not null,
  ${rq("location")} uuid not null references ${location},
  ${rq("supplierType")} text,
  ${rq("supplierId")} text,
  ${rq("currency")} char(3) check (${rq("currency")} ~ '^[A-Z]{3}$'),
  ${rq("status")} text not null default 'pending' check (${rq("status")} in ('pending', 'approved', 'rejected', 'ordered', 'cancelled')),
  ${rq("reason")} text check (length(${rq("reason")}) <= 2000),
  ${rq("requestedBy")} uuid default auth.uid(),
  ${rq("decidedBy")} uuid,
  ${rq("decidedAt")} timestamptz,
  ${rq("approval")} uuid,
  ${rq("purchaseOrder")} uuid references ${t("purchaseOrders")} (${po("id")}) on delete set null,
  ${rq("createdAt")} timestamptz not null default now(),
  ${rq("updatedAt")} timestamptz not null default now(),
  check ((${rq("supplierType")} is null) = (${rq("supplierId")} is null))
);
${index("purchase_requisitions_status_idx", "requisitions", `${rq("tenant")}, ${rq("status")}`)}
${index("purchase_requisitions_location_idx", "requisitions", rq("location"))}
${index("purchase_requisitions_purchase_order_idx", "requisitions", rq("purchaseOrder"))}
${lock("requisitions")}
${read("requisitions")}

create table if not exists ${t("requisitionLines")} (
  ${rl("id")} uuid primary key default gen_random_uuid(),
  ${rl("tenant")} ${ctx.idType} not null,
  ${rl("requisition")} uuid not null references ${t("requisitions")} (${rq("id")}) on delete cascade,
  ${rl("variant")} uuid not null references ${variants},
  ${rl("quantity")} ${QUANTITY} not null check (${rl("quantity")} > 0),
  ${rl("unitCost")} bigint check (${rl("unitCost")} >= 0),
  unique (${rl("requisition")}, ${rl("variant")})
);
${index("purchase_requisition_lines_variant_idx", "requisitionLines", rl("variant"))}
${lock("requisitionLines")}
${read("requisitionLines")}
`
    : "";

  const receipts = hasReceipts(ctx)
    ? `
create table if not exists ${t("receipts")} (
  ${rc("id")} uuid primary key default gen_random_uuid(),
  ${rc("tenant")} ${ctx.idType} not null,
  ${rc("purchaseOrder")} uuid not null references ${t("purchaseOrders")} (${po("id")}) on delete cascade,
  ${rc("location")} uuid not null references ${location},
  ${rc("inspection")} uuid,
  ${rc("receivedBy")} uuid default auth.uid(),
  ${rc("receivedAt")} timestamptz not null default now()
);
${index("inventory_receipts_purchase_order_idx", "receipts", rc("purchaseOrder"))}
${index("inventory_receipts_location_idx", "receipts", rc("location"))}
${lock("receipts")}
${read("receipts")}

create table if not exists ${t("receiptLines")} (
  ${cl("id")} uuid primary key default gen_random_uuid(),
  ${cl("tenant")} ${ctx.idType} not null,
  ${cl("receipt")} uuid not null references ${t("receipts")} (${rc("id")}) on delete cascade,
  ${cl("orderLine")} uuid not null references ${t("purchaseOrderLines")} (${pl("id")}) on delete cascade,
  ${cl("variant")} uuid not null references ${variants},
  ${cl("quantity")} ${QUANTITY} not null check (${cl("quantity")} > 0),
  ${cl("unitCost")} bigint not null check (${cl("unitCost")} >= 0),
  ${cl("detail")} jsonb
);
${index("inventory_receipt_lines_receipt_idx", "receiptLines", cl("receipt"))}
${index("inventory_receipt_lines_order_line_idx", "receiptLines", cl("orderLine"))}
${index("inventory_receipt_lines_variant_idx", "receiptLines", cl("variant"))}
${lock("receiptLines")}
${read("receiptLines")}
`
    : "";

  return `${requisitions}${receipts}`;
}

/**
 * What `receive_purchase_order` adds with receipts: a receipt per call, a line
 * per received line, the `inventory_receipt.created` event and, with
 * `options.receiptInspection`, an inspection of the receipt.
 */
export function receiptSql(ctx: BlockSqlContext): {
  readonly declare: string;
  readonly start: string;
  readonly line: string;
  readonly finish: string;
  readonly result: string;
} {
  if (!hasReceipts(ctx)) {
    return { declare: "", start: "", line: "", finish: "", result: "" };
  }

  const t = (name: string): string => ctx.table(name);
  const rc = columns(ctx, "receipts");
  const cl = columns(ctx, "receiptLines");
  const kind = receiptInspection(ctx);
  const inspections = linked(ctx, "inspections");

  const inspect =
    kind === undefined || inspections === undefined
      ? ""
      : `
  ${asService(`v_inspection := (${inspections.fn("schedule_inspection")}(v_row.tenant, jsonb_build_object('kind', ${sqlString(kind)},
    'title', 'Receipt of purchase order ' || receive_purchase_order.purchase_order::text, 'plannedStart', current_date,
    'auditee', jsonb_build_object('type', ${sqlString(ctx.naming.rename("inventory_receipt"))}, 'id', v_receipt::text))) ->> 'id')::uuid;`)}
  update ${t("receipts")} x set ${rc("inspection")} = v_inspection where x.${rc("id")} = v_receipt;`;

  return {
    declare: `
  v_receipt uuid;${kind === undefined ? "" : "\n  v_inspection uuid;\n  v_claims text;"}`,
    start: `
  insert into ${t("receipts")} (${rc("tenant")}, ${rc("purchaseOrder")}, ${rc("location")})
  values (v_row.tenant, receive_purchase_order.purchase_order, v_row.location)
  returning ${rc("id")} into v_receipt;`,
    line: `
    insert into ${t("receiptLines")} (${cl("tenant")}, ${cl("receipt")}, ${cl("orderLine")}, ${cl("variant")}, ${cl("quantity")}, ${cl("unitCost")}, ${cl("detail")})
    values (v_row.tenant, v_receipt, v_line.id, v_line.variant, v_line.quantity, v_line.unit_cost, nullif(v_line.detail, '{}'::jsonb));`,
    finish: `${inspect}
  ${ctx.record({
    type: "inventory_receipt.created",
    payload: `jsonb_build_object('organizationId', v_row.tenant, 'id', v_receipt, 'purchaseOrderId', receive_purchase_order.purchase_order, 'locationId', v_row.location, 'inspectionId', ${kind === undefined ? "null" : "v_inspection"})`,
    subject: "'inventory-receipts/' || v_receipt::text",
    tenant: "v_row.tenant",
    audit: false,
  })}`,
    result: ", 'receiptId', v_receipt",
  };
}

/** The policy a requisition's approval snapshots when none covers it. */
function defaultPolicy(ctx: BlockSqlContext): string {
  return policySnapshot(
    policyOf(
      ctx.naming.rename("purchase_requisition"),
      "approve",
      {
        steps: [
          {
            approvers: {
              permission: ctx.permissionKey(
                "purchase",
                OPERATIONS["inventory.purchase"],
              ),
            },
          },
        ],
      },
      "blocks.inventory",
    ),
  );
}

/** What approvals runs when a requisition's request is decided. */
export function procurementApprovals(
  own: BlockSqlContext,
): readonly ApprovalContribution[] {
  return hasRequisitions(own)
    ? [
        {
          subject: own.naming.rename("purchase_requisition"),
          access: "declared",
          approve: ({ subjectId }) =>
            `perform ${own.fn("purchase_requisition_decided")}(${subjectId}::uuid, true);`,
          reject: ({ subjectId }) =>
            `perform ${own.fn("purchase_requisition_decided")}(${subjectId}::uuid, false);`,
        },
      ]
    : [];
}

/**
 * Requisitions: `request_purchase`, their decision (through approvals when
 * installed) and `purchase_order_from_requisitions`.
 */
export function requisitionFunctions(
  ctx: BlockSqlContext,
  names: InventoryNames,
): string {
  if (!hasRequisitions(ctx)) {
    return "";
  }

  const { fn } = names;
  const t = (name: string): string => ctx.table(name);
  const rq = columns(ctx, "requisitions");
  const rl = columns(ctx, "requisitionLines");
  const l = locationsOf(ctx);
  const currencyUnits = ctx.of("catalog").fn("currency_minor_units");
  const approvals = linked(ctx, "approvals");
  const subject = sqlString(ctx.naming.rename("purchase_requisition"));

  const event = (type: string, id: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', v_row.${rq("tenant")}, 'id', v_row.${rq("id")}, 'locationId', v_row.${rq("location")}, 'status', v_row.${rq("status")}, 'supplierType', v_row.${rq("supplierType")}, 'supplierId', v_row.${rq("supplierId")})`,
      subject: `'purchase-requisitions/' || ${id}::text`,
      tenant: `v_row.${rq("tenant")}`,
      audit: false,
    });

  const json = (alias: string): string =>
    `jsonb_build_object('id', ${alias}.${rq("id")}, 'organizationId', ${alias}.${rq("tenant")}, 'locationId', ${alias}.${rq("location")},
      'supplierType', ${alias}.${rq("supplierType")}, 'supplierId', ${alias}.${rq("supplierId")}, 'currency', ${alias}.${rq("currency")},
      'status', ${alias}.${rq("status")}, 'reason', ${alias}.${rq("reason")}, 'requestedBy', ${alias}.${rq("requestedBy")},
      'decidedBy', ${alias}.${rq("decidedBy")}, 'decidedAt', ${alias}.${rq("decidedAt")}, 'approvalId', ${alias}.${rq("approval")},
      'createdAt', ${alias}.${rq("createdAt")},
      'purchaseOrderId', ${alias}.${rq("purchaseOrder")},
      'lines', coalesce((select jsonb_agg(jsonb_build_object('id', y.${rl("id")}, 'variantId', y.${rl("variant")}, 'quantity', y.${rl("quantity")}::text,
        'unitCost', y.${rl("unitCost")}::text) order by y.${rl("variant")}) from ${t("requisitionLines")} y where y.${rl("requisition")} = ${alias}.${rq("id")}), '[]'::jsonb))`;

  const openApproval =
    approvals === undefined
      ? ""
      : `
  v_payload := jsonb_build_object('locationId', v_row.${rq("location")}, 'reason', v_row.${rq("reason")},
    'total', (select coalesce(sum(round(y.${rl("quantity")} * coalesce(y.${rl("unitCost")}, 0))), 0)::text from ${t("requisitionLines")} y where y.${rl("requisition")} = v_row.${rq("id")}),
    'currency', v_row.${rq("currency")});
  v_approval := ${approvals.fn("open_approval")}(
    v_row.${rq("tenant")}, ${subject}, v_row.${rq("id")}::text, 'approve',
    coalesce(${approvals.fn("approval_effective_policy")}(v_row.${rq("tenant")}, ${subject}, 'approve', v_payload), ${sqlString(defaultPolicy(ctx))}::jsonb),
    v_row.${rq("reason")}, v_payload
  );
  update ${t("requisitions")} x set ${rq("approval")} = (v_approval ->> 'id')::uuid where x.${rq("id")} = v_row.${rq("id")}
  returning * into v_row;`;

  return `
-- Asks to buy stock for a location. lines: [{ "variantId": uuid, "quantity": n,
-- "unitCost"?: "minor units" }]. A pending requisition waits for its
-- decision: ${approvals === undefined ? "a holder of inventory.purchase approves or rejects it" : "approvals opens a request under the organization's policy for\n-- purchase_requisition approve, or one a holder of inventory.purchase decides"}.
create or replace function ${fn("request_purchase")}(tenant ${ctx.idType}, location uuid, lines jsonb, supplier_type text default null, supplier_id text default null, currency text default null, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("requisitions")};${approvals === undefined ? "" : "\n  v_payload jsonb;\n  v_approval jsonb;"}
begin
  ${guard(names.scope, names.read, "request_purchase.tenant")}
  if not exists (select 1 from ${l.table} x where x.${l.col("id")} = request_purchase.location and x.${l.col("tenant")} = request_purchase.tenant) then
    ${fail("INVENTORY_LOCATION_NOT_FOUND", "location not found in this organization", "P0002")}
  end if;
  if (request_purchase.supplier_type is null) <> (request_purchase.supplier_id is null) then
    ${fail("INVENTORY_SUPPLIER_INVALID", "supplier_type and supplier_id go together", "22023")}
  end if;
  if request_purchase.currency is not null and ${currencyUnits}(request_purchase.currency) is null then
    ${fail("INVENTORY_CURRENCY_INVALID", "the currency must be an ISO 4217 code", "22023")}
  end if;
  ${linesCheck("request_purchase.lines", "variantId", `\n        or (e ? 'unitCost' and coalesce(e ->> 'unitCost', '') !~ ${UNIT_COST})`)}
  ${linesVariantCheck(ctx, "request_purchase.lines", "request_purchase.tenant")}
  insert into ${t("requisitions")} (${rq("tenant")}, ${rq("location")}, ${rq("supplierType")}, ${rq("supplierId")}, ${rq("currency")}, ${rq("reason")})
  values (request_purchase.tenant, request_purchase.location, request_purchase.supplier_type, request_purchase.supplier_id,
    request_purchase.currency, nullif(trim(request_purchase.reason), ''))
  returning * into v_row;
  insert into ${t("requisitionLines")} (${rl("tenant")}, ${rl("requisition")}, ${rl("variant")}, ${rl("quantity")}, ${rl("unitCost")})
  select request_purchase.tenant, v_row.${rq("id")}, (e ->> 'variantId')::uuid, (e ->> 'quantity')::numeric, (e ->> 'unitCost')::bigint
  from jsonb_array_elements(request_purchase.lines) e;
  ${event("purchase_requisition.created", `v_row.${rq("id")}`)}${openApproval}
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("request_purchase")}(${ctx.idType}, uuid, jsonb, text, text, text, text)`)}

-- Settles a pending requisition: approved or rejected. Approvals calls it; it
-- isn't granted to anyone.
create or replace function ${fn("purchase_requisition_decided")}(requisition uuid, approved boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("requisitions")};
begin
  update ${t("requisitions")} x set ${rq("status")} = case when purchase_requisition_decided.approved then 'approved' else 'rejected' end,
    ${rq("decidedBy")} = auth.uid(), ${rq("decidedAt")} = now(), ${rq("updatedAt")} = now()
  where x.${rq("id")} = purchase_requisition_decided.requisition and x.${rq("status")} = 'pending'
  returning * into v_row;
  if found and purchase_requisition_decided.approved then
    ${event("purchase_requisition.approved", `v_row.${rq("id")}`)}
  end if;
end;
$$;
revoke execute on function ${fn("purchase_requisition_decided")}(uuid, boolean) from public, anon, authenticated;

-- Approves (approve true) or rejects a pending requisition. Needs
-- inventory.purchase.${approvals === undefined ? "" : " A requisition with an approval request is decided there."}
create or replace function ${fn("decide_purchase_requisition")}(requisition uuid, approve boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${t("requisitions")};
begin
  select * into v_row from ${t("requisitions")} x where x.${rq("id")} = decide_purchase_requisition.requisition for update;
  if not found then
    ${fail("INVENTORY_REQUISITION_NOT_FOUND", "purchase requisition not found", "P0002")}
  end if;
  ${guard(names.scope, names.purchase, `v_row.${rq("tenant")}`)}
  if v_row.${rq("status")} <> 'pending' then
    ${fail("INVENTORY_REQUISITION_STATUS", "only a pending requisition is decided", "55000")}
  end if;${
    approvals === undefined
      ? ""
      : `
  if v_row.${rq("approval")} is not null then
    ${fail("INVENTORY_REQUISITION_APPROVAL_PENDING", "this requisition is decided through its approval request", "55000")}
  end if;`
  }
  perform ${fn("purchase_requisition_decided")}(v_row.${rq("id")}, coalesce(decide_purchase_requisition.approve, false));
  return (select ${json("x")} from ${t("requisitions")} x where x.${rq("id")} = v_row.${rq("id")});
end;
$$;
${userGrant(`${fn("decide_purchase_requisition")}(uuid, boolean)`)}

-- A draft purchase order from approved requisitions of one location: their
-- lines summed per variant, at the highest unit cost a requisition names
-- (0 when none does; edit the draft before placing it). The supplier and
-- currency default to the ones the requisitions share. The requisitions
-- become ordered.
create or replace function ${fn("purchase_order_from_requisitions")}(requisitions uuid[], supplier_type text default null, supplier_id text default null, currency text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_location uuid;
  v_supplier_type text := purchase_order_from_requisitions.supplier_type;
  v_supplier_id text := purchase_order_from_requisitions.supplier_id;
  v_currency text := upper(purchase_order_from_requisitions.currency);
  v_lines jsonb;
  v_order jsonb;
begin
  if coalesce(cardinality(purchase_order_from_requisitions.requisitions), 0) = 0 then
    ${fail("INVENTORY_REQUISITION_NOT_FOUND", "name at least one requisition", "22023")}
  end if;
  perform 1 from ${t("requisitions")} x where x.${rq("id")} = any (purchase_order_from_requisitions.requisitions) for update;
  if (select count(*) from ${t("requisitions")} x where x.${rq("id")} = any (purchase_order_from_requisitions.requisitions))
    <> (select count(distinct r) from unnest(purchase_order_from_requisitions.requisitions) r) then
    ${fail("INVENTORY_REQUISITION_NOT_FOUND", "purchase requisition not found", "P0002")}
  end if;
  if (select count(distinct x.${rq("tenant")}) + count(distinct x.${rq("location")}) from ${t("requisitions")} x where x.${rq("id")} = any (purchase_order_from_requisitions.requisitions)) <> 2 then
    ${fail("INVENTORY_REQUISITION_MIXED", "requisitions on one purchase order share an organization and a location", "22023")}
  end if;
  select x.${rq("tenant")}, x.${rq("location")} into v_tenant, v_location
  from ${t("requisitions")} x where x.${rq("id")} = purchase_order_from_requisitions.requisitions[1];
  ${guard(names.scope, names.purchase, "v_tenant")}
  if exists (select 1 from ${t("requisitions")} x where x.${rq("id")} = any (purchase_order_from_requisitions.requisitions) and x.${rq("status")} <> 'approved') then
    ${fail("INVENTORY_REQUISITION_STATUS", "only approved requisitions become a purchase order", "55000")}
  end if;
  if v_supplier_id is null then
    select min(x.${rq("supplierType")}), min(x.${rq("supplierId")}) into v_supplier_type, v_supplier_id
    from ${t("requisitions")} x where x.${rq("id")} = any (purchase_order_from_requisitions.requisitions)
    having count(distinct coalesce(x.${rq("supplierType")}, '') || ':' || coalesce(x.${rq("supplierId")}, '')) = 1;
  end if;
  if v_currency is null then
    select min(x.${rq("currency")}) into v_currency
    from ${t("requisitions")} x where x.${rq("id")} = any (purchase_order_from_requisitions.requisitions)
    having count(distinct x.${rq("currency")}) = 1;
  end if;
  select jsonb_agg(jsonb_build_object('variantId', y.variant, 'quantity', y.quantity::text, 'unitCost', y.unit_cost::text)) into v_lines
  from (
    select l.${rl("variant")} as variant, sum(l.${rl("quantity")}) as quantity, coalesce(max(l.${rl("unitCost")}), 0) as unit_cost
    from ${t("requisitionLines")} l where l.${rl("requisition")} = any (purchase_order_from_requisitions.requisitions)
    group by 1
  ) y;
  v_order := ${fn("save_purchase_order")}(v_tenant, null, v_location, v_supplier_type, v_supplier_id, v_currency, null, v_lines, null);
  update ${t("requisitions")} x set ${rq("status")} = 'ordered', ${rq("purchaseOrder")} = (v_order ->> 'id')::uuid, ${rq("updatedAt")} = now()
  where x.${rq("id")} = any (purchase_order_from_requisitions.requisitions);
  return v_order;
end;
$$;
${userGrant(`${fn("purchase_order_from_requisitions")}(uuid[], text, text, text)`)}

-- A requisition with its lines, readable by a holder of inventory.read.
create or replace function ${fn("get_purchase_requisition")}(requisition uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${t("requisitions")};
begin
  select * into v_row from ${t("requisitions")} x where x.${rq("id")} = get_purchase_requisition.requisition;
  if not found then
    ${fail("INVENTORY_REQUISITION_NOT_FOUND", "purchase requisition not found", "P0002")}
  end if;
  ${guard(names.scope, names.read, `v_row.${rq("tenant")}`)}
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("get_purchase_requisition")}(uuid)`)}`;
}

export function procurementContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  return hasRequisitions(ctx)
    ? [
        {
          name: "request_purchase",
          args: ["{id}", "uuid", "jsonb", "text", "text", "text", "text"],
          returns: "jsonb",
        },
        {
          name: "decide_purchase_requisition",
          args: ["uuid", "boolean"],
          returns: "jsonb",
        },
        {
          name: "purchase_order_from_requisitions",
          args: ["uuid[]", "text", "text", "text"],
          returns: "jsonb",
        },
        { name: "get_purchase_requisition", args: ["uuid"], returns: "jsonb" },
      ]
    : [];
}
