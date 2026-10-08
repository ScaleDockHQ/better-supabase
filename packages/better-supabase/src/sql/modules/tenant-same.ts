import type { ModuleContext } from "../context.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { quotedTable } from "../shared.ts";

interface SameTenant {
  readonly table: string;
  readonly column: string;
  readonly tenant: string;
  readonly parent: string;
  readonly key: string;
  readonly parentTenant: string;
  readonly where: string | undefined;
  readonly match: readonly (readonly [string, string])[];
  readonly hops: readonly Hop[];
}

interface Hop {
  readonly via: string;
  readonly table: string;
  readonly key: string;
  readonly column: string;
  readonly referenced: string;
}

const IDENT = /^[a-z_][a-z0-9_$]{0,62}$/;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

function entriesOf(ctx: ModuleContext): readonly SameTenant[] {
  const where = "sql.modules.tenant.options.sameTenant";
  const value = ctx.option("sameTenant");
  if (value === undefined) return [];
  if (!Array.isArray(value)) {
    throw new TypeError(
      `${where} must be a list of { table, column, references, tenant?, match?, through? }`,
    );
  }
  const fallback = ctx.col("memberships", "tenant").replaceAll('"', "");
  const ident = (at: string, name: unknown, otherwise?: string): string => {
    const resolved = name ?? otherwise;
    if (typeof resolved !== "string" || !IDENT.test(resolved)) {
      throw new TypeError(`${at} must be a lowercase column name`);
    }
    return resolved;
  };
  return value.map((entry: unknown, index): SameTenant => {
    const at = `${where}[${String(index)}]`;
    if (
      !isRecord(entry) ||
      typeof entry["table"] !== "string" ||
      (typeof entry["references"] !== "string" &&
        !isRecord(entry["references"]))
    ) {
      throw new TypeError(
        `${at} must be { table: "schema.table", column: "<column>", references: "schema.table" | { table, column?, tenant?, where? }, tenant?, match?, through? }`,
      );
    }
    const references: Record<string, unknown> =
      typeof entry["references"] === "string"
        ? { table: entry["references"] }
        : entry["references"];
    if (typeof references["table"] !== "string") {
      throw new TypeError(`${at}.references.table must be "schema.table"`);
    }
    const condition = references["where"];
    if (
      condition !== undefined &&
      (typeof condition !== "string" || !condition.includes("{row}"))
    ) {
      throw new TypeError(
        `${at}.references.where must be a condition on {row}`,
      );
    }
    const match = entry["match"] ?? {};
    if (!isRecord(match)) {
      throw new TypeError(
        `${at}.match must be { <column>: "<referenced column>" }`,
      );
    }
    const through = entry["through"] ?? {};
    if (!isRecord(through)) {
      throw new TypeError(
        `${at}.through must be { <column>: "schema.table" | { table, column? } }`,
      );
    }
    const pairs: (readonly [string, string])[] = [];
    const hops: Hop[] = [];
    for (const [own, referenced] of Object.entries(match)) {
      const dot = own.indexOf(".");
      if (dot === -1) {
        pairs.push([
          ident(`${at}.match`, own),
          ident(`${at}.match.${own}`, referenced),
        ]);
        continue;
      }
      const via = ident(`${at}.match`, own.slice(0, dot));
      const column = ident(`${at}.match`, own.slice(dot + 1));
      const target = through[via];
      const hop: Record<string, unknown> | undefined =
        typeof target === "string"
          ? { table: target }
          : isRecord(target)
            ? target
            : undefined;
      if (hop === undefined || typeof hop["table"] !== "string") {
        throw new TypeError(
          `${at}.match.${own} reads ${via}, so ${at}.through.${via} must name the table ${via} references`,
        );
      }
      hops.push({
        via,
        table: quotedTable(hop["table"]),
        key: ident(`${at}.through.${via}.column`, hop["column"], "id"),
        column,
        referenced: ident(`${at}.match.${own}`, referenced),
      });
    }
    const tenant = ident(`${at}.tenant`, entry["tenant"], fallback);
    return {
      table: quotedTable(entry["table"]),
      column: ident(`${at}.column`, entry["column"]),
      tenant,
      parent: quotedTable(references["table"]),
      key: ident(`${at}.references.column`, references["column"], "id"),
      parentTenant: ident(
        `${at}.references.tenant`,
        references["tenant"],
        tenant,
      ),
      where: condition,
      match: pairs,
      hops,
    };
  });
}

/** A trigger name for `column`, within Postgres' 63 bytes. */
function triggerName(column: string): string {
  return sqlIdent(`bs_same_tenant_${column}`.slice(0, 63));
}

/**
 * `sql.modules.tenant.options.sameTenant`: one `same_tenant()` trigger per
 * entry, so a reference to a row of another tenant fails for every writer.
 * Empty without entries.
 */
export function sameTenantSql(ctx: ModuleContext): string {
  const entries = entriesOf(ctx);
  if (entries.length === 0) return "";
  const triggers = entries.map((entry) => {
    const conditions = [
      ...(entry.where === undefined
        ? []
        : [entry.where.replaceAll("{row}", "p")]),
      ...entry.hops.map(
        (hop) =>
          `p.${sqlIdent(hop.referenced)} is not distinct from (select h.${sqlIdent(hop.column)} from ${hop.table} h where h.${sqlIdent(hop.key)} = ($1).${sqlIdent(hop.via)})`,
      ),
    ];
    const condition =
      conditions.length > 1
        ? conditions.map((part) => `(${part})`).join(" and ")
        : conditions[0];
    const args = [
      entry.column,
      entry.tenant,
      entry.parent,
      entry.key,
      entry.parentTenant,
      ...(condition === undefined && entry.match.length === 0
        ? []
        : [condition ?? ""]),
      ...entry.match.flat(),
    ].map(sqlString);
    const name = triggerName(entry.column);
    const columns = [
      ...new Set([
        entry.column,
        entry.tenant,
        ...entry.match.map(([own]) => own),
        ...entry.hops.map((hop) => hop.via),
      ]),
    ]
      .map(sqlIdent)
      .join(", ");
    return `drop trigger if exists ${name} on ${entry.table};
create trigger ${name} before insert or update of ${columns} on ${entry.table}
  for each row execute function better_supabase.same_tenant(${args.join(", ")});`;
  });
  return `
-- sql.modules.tenant.options.sameTenant: a row may reference only a row of
-- its own tenant, whoever writes it (a client policy, the service role or an
-- admin connection). Arguments: the column, the row's tenant column, the
-- referenced table, its key and tenant columns, and an optional condition on
-- the referenced row p. A null reference passes; the foreign key, if any,
-- still checks that the row exists.
create or replace function better_supabase.same_tenant()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  matched boolean;
  extra text := '';
  i integer := 6;
begin
  if pg_catalog.to_jsonb(new) -> tg_argv[0] = 'null'::jsonb then
    return new;
  end if;
  if tg_nargs > 5 and tg_argv[5] <> '' then
    extra := ' and (' || tg_argv[5] || ')';
  end if;
  while i + 1 < tg_nargs loop
    extra := extra || pg_catalog.format(' and p.%I is not distinct from ($1).%I', tg_argv[i + 1], tg_argv[i]);
    i := i + 2;
  end loop;
  execute pg_catalog.format(
    'select exists (select 1 from %s p where p.%I = ($1).%I and p.%I is not distinct from ($1).%I%s)',
    tg_argv[2], tg_argv[3], tg_argv[0], tg_argv[4], tg_argv[1], extra
  ) into matched using new;
  if not matched then
    raise exception '%.% must reference a row of % in the same tenant', tg_table_name, tg_argv[0], tg_argv[2]
      using errcode = '23514', hint = 'TENANT_MISMATCH';
  end if;
  return new;
end;
$$;
revoke execute on function better_supabase.same_tenant() from public, anon, authenticated;
${triggers.join("\n")}
`;
}
