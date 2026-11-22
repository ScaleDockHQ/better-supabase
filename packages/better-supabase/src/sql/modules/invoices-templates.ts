import type { BlockSqlContext } from "../context.ts";
import type { InvoiceNames } from "./invoices-names.ts";

import { sqlString } from "../../core/template.ts";
import { fail, userGrant } from "../shared.ts";
import { cloneTenant, headerPairs, partyPairs } from "./templates-clone.ts";

/** Template rows are on for invoices (ADR 0244). */
export function invoiceTemplatesOn(ctx: BlockSqlContext): boolean {
  if (!ctx.flag("templates", false)) {
    return false;
  }

  if (!ctx.installed("templates")) {
    throw new TypeError(
      "blocks.invoices.options.templates needs the templates block",
    );
  }

  return ctx.has("invoices", "template");
}

/** `clone_invoice`: a new invoice from an invoice or a template, with its lines. */
export function cloneInvoice(
  ctx: BlockSqlContext,
  n: InvoiceNames,
  fn: (name: string) => string,
  t: (table: string) => string,
  i: (column: string) => string,
  row: (alias: string) => string,
): string {
  const on = invoiceTemplatesOn(ctx);

  const template = on
    ? "case when coalesce(clone_invoice.overrides, '{}'::jsonb) ? 'templateId' then clone_invoice.overrides ->> 'templateId' else null end"
    : "null";

  const copied = ctx.has("invoices", "sourceTemplate")
    ? `v_src.${i("sourceTemplate")}::text`
    : "null";

  const source = on
    ? `case when v_src.${i("template")} is not null then v_src.${i("template")}::text else ${copied} end`
    : "null";

  const parentKey = sqlString(ctx.colName("lines", "parent"));

  const header = [
    headerPairs(ctx, "invoices", "v_src", i, [
      ["note", "note"],
      ["termsDays", "termsDays"],
      ["pricesIncludeTax", "pricesIncludeTax"],
      ["discountBps", "discountBps"],
      ["discountAmount", "discountAmount"],
      ["depositBps", "depositBps"],
      ["depositAmount", "depositAmount"],
    ]),
    partyPairs(ctx, "invoices", "v_src", i),
  ]
    .filter((part) => part !== "")
    .map((part) => `${part}, `)
    .join("");

  const owned = ctx.has("invoices", "template")
    ? `v_src.${i("template")} is not null`
    : "false";

  const linesTenant = ctx.has("lines", "tenant")
    ? `, ${sqlString(ctx.colName("lines", "tenant"))}, v_tenant`
    : "";

  return [
    `create or replace function ${fn("clone_invoice")}(source uuid, overrides jsonb default null)`,
    "returns jsonb",
    "language plpgsql",
    "security definer",
    "set search_path = ''",
    "as $$",
    "declare",
    `  v_src ${t("invoices")};`,
    "  v_created jsonb;",
    "  v_id uuid;",
    `  v_tenant ${ctx.idType};`,
    "begin",
    `  select * into v_src from ${t("invoices")} x where x.${i("id")} = clone_invoice.source;`,
    "  if not found then",
    `    ${fail("INVOICE_NOT_FOUND", "no such invoice", "P0002")}`,
    "  end if;",
    `  ${cloneTenant(ctx, { fn: "clone_invoice", code: "INVOICE_FORBIDDEN", source: "v_src", tenant: i("tenant"), owned, service: n.service, can: n.write, message: "not allowed to change invoices" })}`,
    `  ${ctx.hook("before_invoice_clone", [
      ["uuid", "clone_invoice.source"],
      ["jsonb", "clone_invoice.overrides"],
    ])}`,
    `  v_created := ${fn("create_invoice")}(v_tenant, jsonb_strip_nulls(jsonb_build_object(${header}'title', v_src.${i("title")}, 'currency', v_src.${i("currency")}, 'templateId', ${template}, 'sourceTemplateId', ${source})) || (coalesce(clone_invoice.overrides, '{}'::jsonb) - 'templateId') || jsonb_strip_nulls(jsonb_build_object('templateId', ${template}, 'sourceTemplateId', ${source})), null);`,
    "  v_id := (v_created ->> 'id')::uuid;",
    `  insert into ${t("lines")}`,
    `  select (jsonb_populate_record(null::${t("lines")}, to_jsonb(l) || jsonb_build_object('id', gen_random_uuid(), ${parentKey}, v_id${linesTenant}))).*`,
    `  from ${t("lines")} l where l.${ctx.col("lines", "parent")} = clone_invoice.source;`,
    `  ${ctx.hook("after_invoice_clone", [["uuid", "v_id"]])}`,
    `  return (select ${row("x")} from ${t("invoices")} x where x.${i("id")} = v_id);`,
    "end;",
    "$$;",
    userGrant(`${fn("clone_invoice")}(uuid, jsonb)`),
  ].join("\n");
}
