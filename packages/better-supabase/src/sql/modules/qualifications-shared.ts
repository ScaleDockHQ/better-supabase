import type { BlockSqlContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";

/** The keys the holding reads return next to the extra columns. */
export const QUALIFICATION_RESERVED = [
  "fields",
  "status",
  "typeKey",
  "typeName",
] as const;

/** The holders a qualification type may name. */
export const HOLDER_TYPES = ["member", "company", "asset"] as const;

/** What a requirement targets, and the holder type each one applies to. */
export const TARGET_TYPES = {
  role: "member",
  team: "member",
  job_title: "member",
  asset_kind: "asset",
  segment: "company",
  holder: undefined,
} as const;

/** How a holding came to be. */
export const SOURCES = ["manual", "course", "import"] as const;

/** The holder types `blocks.qualifications.options.holderTypes` allows. */
export function holderTypes(ctx: BlockSqlContext): readonly string[] {
  const list = ctx.list("holderTypes", HOLDER_TYPES);

  const known = new Set<string>(HOLDER_TYPES);
  const unknown = list.filter((type) => !known.has(type));

  if (list.length === 0 || unknown.length > 0) {
    throw new TypeError(
      `blocks.qualifications.options.holderTypes takes ${HOLDER_TYPES.join(", ")}${unknown.length > 0 ? `, not ${unknown.join(", ")}` : ""}`,
    );
  }

  return list;
}

/** Days before expiry a holding counts as expiring. */
export function renewalWindow(ctx: BlockSqlContext): number {
  const days = ctx.number("renewalWindowDays", 30);

  if (!Number.isInteger(days) || days < 0 || days > 3650) {
    throw new TypeError(
      "blocks.qualifications.options.renewalWindowDays takes a whole number of days from 0 to 3650",
    );
  }

  return days;
}

/** `('a', 'b')` for an `in` list. */
export const sqlList = (values: readonly string[]): string =>
  `(${values.map((value) => sqlString(value)).join(", ")})`;

/** `row.column`, or null when the app's table lacks the optional column. */
export const optionalField = (
  ctx: BlockSqlContext,
  table: string,
  row: string,
  column: string,
): string =>
  ctx.has(table, column) ? `${row}.${ctx.col(table, column)}` : "null";

/**
 * A holding's status on `current_date`: revoked, expired, expiring (inside the
 * renewal window) or valid.
 */
export function holdingStatus(ctx: BlockSqlContext, row: string): string {
  const q = (column: string): string =>
    `${row}.${ctx.col("qualifications", column)}`;

  const days = renewalWindow(ctx);

  return `case
    when ${q("revokedAt")} is not null then 'revoked'
    when ${q("expiresOn")} is not null and ${q("expiresOn")} < current_date then 'expired'
    when ${q("expiresOn")} is not null and ${q("expiresOn")} <= current_date + ${String(days)} then 'expiring'
    else 'valid'
  end`;
}

/** The attachments module, when its table is there to reference. */
export function evidenceAttachments(
  ctx: BlockSqlContext,
): BlockSqlContext | undefined {
  return ctx.installed("attachments") && ctx.of("attachments").manages
    ? ctx.of("attachments")
    : undefined;
}

/**
 * A text expression naming holder `id` (text) of `type`: the employee's name or
 * the member's email, the company's name, or the asset's name. Empty when the
 * module behind the holder type isn't installed.
 */
export function holderTitle(
  ctx: BlockSqlContext,
  type: string,
  id: string,
  tenant: string,
): string | undefined {
  switch (type) {
    case "member": {
      const users = `(select u.email::text from auth.users u where u.id::text = ${id})`;

      if (!ctx.installed("employees")) {
        return `coalesce(${users}, ${id})`;
      }

      const people = ctx.of("employees");
      const e = (column: string): string => people.col("employees", column);

      const name = people.has("employees", "name")
        ? `e.${e("name")}`
        : people.has("employees", "firstName") &&
            people.has("employees", "lastName")
          ? `nullif(trim(concat_ws(' ', e.${e("firstName")}, e.${e("lastName")})), '')`
          : undefined;

      return name === undefined
        ? `coalesce(${users}, ${id})`
        : `coalesce((select ${name} from ${people.table("employees")} e where e.${e("tenant")} = ${tenant} and e.${e("user")}::text = ${id} limit 1), ${users}, ${id})`;
    }

    case "company": {
      if (!ctx.installed("contacts")) {
        return undefined;
      }

      const contacts = ctx.of("contacts");
      const c = (column: string): string => contacts.col("companies", column);

      return `coalesce((select c.${c("name")}::text from ${contacts.table("companies")} c where c.${c("id")}::text = ${id}), ${id})`;
    }

    case "asset": {
      if (!ctx.installed("assets")) {
        return undefined;
      }

      const assets = ctx.of("assets");
      const a = (column: string): string => assets.col("assets", column);

      return `coalesce((select a.${a("name")}::text from ${assets.table("assets")} a where a.${a("id")}::text = ${id}), ${id})`;
    }

    default: {
      return undefined;
    }
  }
}
