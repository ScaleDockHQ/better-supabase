import type { BlockSqlContext } from "../context.ts";

import { fail, serviceGrant, userGrant } from "../shared.ts";
import { OPERATIONS } from "./permissions-model.ts";

const EVENT_MODES: ReadonlySet<string> = new Set(["skip", "tag", "emit"]);

/** `blocks.imports.options.events` as JSON. A missing entry skips the event. */
export function eventsPolicyOf(ctx: BlockSqlContext): string {
  const where = "blocks['imports'].options.events";
  const raw: unknown = ctx.option("events") ?? {};

  if (typeof raw !== "object" || raw === null || Array.isArray(raw)) {
    throw new TypeError(
      `${where} must map event types (or "default") to skip, tag or emit`,
    );
  }

  const policy: Record<string, string> = {};

  for (const [type, mode] of new Map<string, unknown>(Object.entries(raw))) {
    if (typeof mode !== "string" || !EVENT_MODES.has(mode)) {
      throw new TypeError(`${where}.${type} must be skip, tag or emit`);
    }

    policy[type] = mode;
  }

  return JSON.stringify(policy);
}

/**
 * Generic integrity checks an import can run on the library's own tables. Each
 * check returns a count and a capped sample of ids.
 */
export function importIntegritySql(ctx: BlockSqlContext): string {
  const fn = (name: string): string => ctx.fn(name);
  const records = ctx.table("records");
  const x = (column: string): string => ctx.col("records", column);

  const checks: string[] = [
    `select 'duplicate_keys', 'error', count(*)::integer, coalesce(jsonb_agg(sample), '[]'::jsonb) from (
      select min(d.${x("id")}::text) as sample from ${records} d
      where d.${x("tenant")} = import_integrity.tenant
        and (import_integrity.source is null or d.${x("source")} = import_integrity.source)
      group by d.${x("entity")}, d.${x("externalKey")}
      having count(distinct d.${x("subjectId")}) > 1
    ) q`,
  ];

  if (ctx.installed("ledger")) {
    const ledger = ctx.of("ledger");
    const entries = ledger.table("entries");
    const transactions = ledger.table("transactions");
    const e = (column: string): string => ledger.col("entries", column);
    const t = (column: string): string => ledger.col("transactions", column);

    checks.push(`select 'unbalanced_ledger', 'error', count(*)::integer, coalesce(jsonb_agg(sample), '[]'::jsonb) from (
      select e.${e("transaction")}::text as sample from ${entries} e
      join ${transactions} y on y.${t("id")} = e.${e("transaction")}
      where y.${t("tenant")} = import_integrity.tenant
      group by e.${e("transaction")}
      having sum(e.${e("amount")}) <> 0
    ) q`);
  }

  if (ctx.installed("invoices")) {
    const invoices = ctx.of("invoices");
    const table = invoices.table("invoices");
    const i = (column: string): string => invoices.col("invoices", column);

    checks.push(
      `select 'negative_invoice', 'warning', count(*)::integer, coalesce(jsonb_agg(${i("id")}::text), '[]'::jsonb) from ${table} where ${i("tenant")} = import_integrity.tenant and ${i("total")} < 0 and ${i("kind")}::text is distinct from 'credit_note'`,
      `select 'issued_without_number', 'warning', count(*)::integer, coalesce(jsonb_agg(${i("id")}::text), '[]'::jsonb) from ${table} where ${i("tenant")} = import_integrity.tenant and ${i("status")}::text in ('issued', 'partially_paid', 'paid') and nullif(${i("identifier")}::text, '') is null`,
    );
  }

  if (ctx.installed("contacts")) {
    const contacts = ctx.of("contacts");
    const companies = contacts.table("companies");
    const c = (column: string): string => contacts.col("companies", column);

    checks.push(
      `select 'archived_without_date', 'warning', count(*)::integer, coalesce(jsonb_agg(${c("id")}::text), '[]'::jsonb) from ${companies} where ${c("tenant")} = import_integrity.tenant and ${c("lifecycle")}::text = 'archived' and ${c("archivedAt")} is null`,
    );
  }

  return `
create or replace function ${fn("import_integrity")}(tenant ${ctx.idType}, source text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_checks jsonb := '[]'::jsonb;
  v_name text;
  v_severity text;
  v_count integer;
  v_ids jsonb;
begin
  if not (auth.role() = 'service_role' or ${ctx.scope.can("import_integrity.tenant", ctx.permission("manage", OPERATIONS["imports.manage"]))}) then
    ${fail("IMPORT_FORBIDDEN", "not allowed to check this import", "42501")}
  end if;
  for v_name, v_severity, v_count, v_ids in
    ${checks.join("\n    union all\n    ")}
  loop
    v_checks := v_checks || jsonb_build_array(jsonb_build_object(
      'name', v_name, 'severity', v_severity, 'count', v_count, 'ids', coalesce(v_ids, '[]'::jsonb)));
  end loop;
  return jsonb_build_object('checks', v_checks);
end;
$$;
${serviceGrant(`${fn("import_integrity")}(${ctx.idType}, text)`)}
${userGrant(`${fn("import_integrity")}(${ctx.idType}, text)`)}
`;
}
