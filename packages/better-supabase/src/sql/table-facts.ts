import type { ExposeConfig, ResolvedExpose } from "../config/expose.ts";
import type { BsbTag } from "./bsb-tags.ts";

import { resolveExpose } from "../config/expose.ts";
import { parseBsbComment } from "./bsb-tags.ts";

/** The tags that carry table facts config used to hold. */
export const TABLE_FACT_TAGS = [
  "audit-exempt",
  "data-lifecycle",
  "grant",
  "same-tenant",
  "same-tenant=false",
] as const;

const tagOf = (comment: string | null, name: string): BsbTag | undefined =>
  parseBsbComment(comment).tags.find((tag) => tag.name === name);

const text = (value: string | true | undefined): string | undefined =>
  typeof value === "string" ? value : undefined;

/** Splits at commas outside parentheses: `select,update(a, b)`. */
export function splitList(value: string): string[] {
  const items: string[] = [];
  let depth = 0;
  let current = "";

  for (const char of value) {
    if (char === "(") {
      depth += 1;
    } else if (char === ")") {
      depth -= 1;
    }

    if (char === "," && depth === 0) {
      items.push(current.trim());
      current = "";
    } else {
      current += char;
    }
  }

  items.push(current.trim());

  return items.filter((item) => item !== "");
}

/**
 * `@bsb audit-exempt reason="..."`. The reason is `undefined` when it is
 * missing.
 */
export function auditExemptTag(
  comment: string | null,
): { readonly reason: string | undefined } | undefined {
  const tag = tagOf(comment, "audit-exempt");

  if (tag === undefined) {
    return undefined;
  }

  const reason = text(tag.args["reason"])?.trim();

  return { reason: reason === "" ? undefined : reason };
}

/** A `data-lifecycle` tag, as an `options.tables` entry. */
export interface LifecycleFact {
  readonly user?: string;
  readonly tenant?: string;
  readonly export?: boolean;
  readonly purge?: boolean;
  readonly omit?: readonly string[];
}

function flag(
  value: string | true | undefined,
  name: string,
  tag = "data-lifecycle",
): boolean | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (value === true || value === "true") {
    return true;
  }

  if (value === "false") {
    return false;
  }

  throw new TypeError(`@bsb ${tag}: ${name} must be true or false`);
}

/** `@bsb data-lifecycle user= tenant= export=false purge=false omit=a,b`. */
export function lifecycleTag(
  comment: string | null,
): LifecycleFact | undefined {
  const tag = tagOf(comment, "data-lifecycle");

  if (tag === undefined) {
    return undefined;
  }

  const user = text(tag.args["user"]);
  const tenant = text(tag.args["tenant"]);
  const exported = flag(tag.args["export"], "export");
  const purge = flag(tag.args["purge"], "purge");
  const omit = text(tag.args["omit"]);

  return {
    ...(user === undefined ? {} : { user }),
    ...(tenant === undefined ? {} : { tenant }),
    ...(exported === undefined ? {} : { export: exported }),
    ...(purge === undefined ? {} : { purge }),
    ...(omit === undefined ? {} : { omit: splitList(omit) }),
  };
}

/** A `grant` tag: the privileges each Data API role gets on the table. */
export interface GrantFact {
  readonly anon?: readonly string[];
  readonly authenticated?: readonly string[];
  readonly serviceRole?: readonly string[];
}

/** `@bsb grant authenticated="select,update(title, body)" anon=select`. */
export function grantTag(comment: string | null): GrantFact | undefined {
  const tag = tagOf(comment, "grant");

  if (tag === undefined) {
    return undefined;
  }

  const roles = {
    anon: text(tag.args["anon"]),
    authenticated: text(tag.args["authenticated"]),
    serviceRole: text(tag.args["service-role"]),
  };

  return Object.fromEntries(
    Object.entries(roles).flatMap(([role, value]) =>
      value === undefined ? [] : [[role, splitList(value)]],
    ),
  );
}

/**
 * The grants of a `grant` tag, checked as `expose.<table>` is. Throws on an
 * unknown privilege.
 */
export function grantExpose(table: string, fact: GrantFact): ResolvedExpose {
  // SAFETY: resolveExpose validates each privilege string and throws on a bad one.
  const entry = fact as ExposeConfig;

  return resolveExpose(table, entry);
}

/** What a `same-tenant` column tag says about the foreign key it sits on. */
export type SameTenantFact =
  | { readonly skip: true }
  | {
      readonly skip?: false;
      readonly where?: string;
      readonly match?: Readonly<Record<string, string>>;
      readonly through?: Readonly<Record<string, string>>;
      /** The row's tenant column, when it is not the memberships one. */
      readonly tenant?: string;
      /** The referenced table's tenant column, when it differs. */
      readonly parentTenant?: string;
      /**
       * A referenced row with no tenant passes. Unset follows the column's
       * nullability.
       */
      readonly shared?: boolean;
    };

function pairs(
  value: string | true | undefined,
  name: string,
): Record<string, string> | undefined {
  if (typeof value !== "string") {
    return undefined;
  }

  return Object.fromEntries(
    splitList(value).map((item) => {
      const at = item.indexOf("=");

      if (at === -1) {
        throw new TypeError(
          `@bsb same-tenant: ${name} entries are a=b, got "${item}"`,
        );
      }

      return [item.slice(0, at).trim(), item.slice(at + 1).trim()];
    }),
  );
}

/**
 * `@bsb same-tenant where=... match=a=b through=via=schema.table tenant=col
 * parent-tenant=col shared=false`, or `same-tenant=false`.
 */
export function sameTenantTag(
  comment: string | null,
): SameTenantFact | undefined {
  if (tagOf(comment, "same-tenant=false") !== undefined) {
    return { skip: true };
  }

  const tag = tagOf(comment, "same-tenant");

  if (tag === undefined) {
    return undefined;
  }

  const where = text(tag.args["where"]);
  const match = pairs(tag.args["match"], "match");
  const through = pairs(tag.args["through"], "through");
  const tenant = text(tag.args["tenant"]);
  const parentTenant = text(tag.args["parent-tenant"]);
  const shared = flag(tag.args["shared"], "shared", "same-tenant");

  return {
    ...(where === undefined ? {} : { where }),
    ...(match === undefined ? {} : { match }),
    ...(through === undefined ? {} : { through }),
    ...(tenant === undefined ? {} : { tenant }),
    ...(parentTenant === undefined ? {} : { parentTenant }),
    ...(shared === undefined ? {} : { shared }),
  };
}

const COLUMN_COMMENT =
  /comment\s+on\s+column\s+(?:"?([a-z_][a-z0-9_]*)"?\.)?"?([a-z_][a-z0-9_]*)"?\."?([a-z_][a-z0-9_]*)"?\s+is\s+'((?:[^']|'')*)'\s*;/giu;

/** A column comment that carries `@bsb` tags. */
export interface ColumnTagComment {
  readonly schema: string;
  readonly name: string;
  readonly column: string;
  readonly comment: string;
}

/** The `@bsb` column comments in `sql`, with an unqualified table in `public`. */
export function columnTagComments(sql: string): ColumnTagComment[] {
  return [...sql.matchAll(COLUMN_COMMENT)].flatMap((match) => {
    const comment = match[4]?.replaceAll("''", "'");
    const name = match[2];
    const column = match[3];

    return comment !== undefined &&
      name !== undefined &&
      column !== undefined &&
      parseBsbComment(comment).tags.length > 0
      ? [{ schema: match[1] ?? "public", name, column, comment }]
      : [];
  });
}

/** The `same-tenant` column tags, as `sameTenant` entries and skipped columns. */
export interface SameTenantTags {
  readonly entries: readonly Record<string, unknown>[];
  /** `schema.table.column` of each column tagged `same-tenant=false`. */
  readonly skip: readonly string[];
}

/**
 * Reads the `same-tenant` tags of the column comments in `texts`. A tagged
 * column with no foreign key is left out, and BS703 reports it. An entry
 * carries `shared` only when the tag sets it; the block otherwise follows the
 * nullability of the referenced tenant column.
 */
export function sameTenantTagsOf(
  texts: readonly string[],
  schemas: readonly string[],
  foreignKeys: readonly {
    readonly table: string;
    readonly columns: readonly string[];
    readonly references: string;
    readonly referencedColumns: readonly string[];
    readonly deferrable?: boolean;
  }[],
): SameTenantTags {
  const entries: Record<string, unknown>[] = [];
  const skip: string[] = [];

  for (const text of texts) {
    for (const found of columnTagComments(text)) {
      const fact = sameTenantTag(found.comment);

      if (fact === undefined || !schemas.includes(found.schema)) {
        continue;
      }

      const table = `${found.schema}.${found.name}`;

      if (fact.skip === true) {
        skip.push(`${table}.${found.column}`);
        continue;
      }

      // A single-column key on the column wins; otherwise a composite key that
      // holds it, whose other columns become `match` pairs.
      const key =
        foreignKeys.find(
          (candidate) =>
            candidate.table === table &&
            candidate.columns.length === 1 &&
            candidate.columns[0] === found.column,
        ) ??
        foreignKeys.find(
          (candidate) =>
            candidate.table === table &&
            candidate.columns.includes(found.column),
        );

      const at = key?.columns.indexOf(found.column) ?? -1;
      const referenced = key?.referencedColumns[at];

      if (key === undefined || referenced === undefined) {
        continue;
      }

      const companions = Object.fromEntries(
        key.columns.flatMap((column, index) => {
          const other = key.referencedColumns[index];

          return index === at || other === undefined ? [] : [[column, other]];
        }),
      );

      const match = { ...companions, ...fact.match };

      entries.push({
        table,
        column: found.column,
        ...(fact.tenant === undefined ? {} : { tenant: fact.tenant }),
        references: {
          table: key.references,
          column: referenced,
          ...(fact.where === undefined ? {} : { where: fact.where }),
          ...(fact.parentTenant === undefined
            ? {}
            : { tenant: fact.parentTenant }),
        },
        ...(Object.keys(match).length === 0 ? {} : { match }),
        ...(fact.through === undefined ? {} : { through: fact.through }),
        ...(key.deferrable === true ? { deferrable: true } : {}),
        ...(fact.shared === undefined ? {} : { shared: fact.shared }),
      });
    }
  }

  return { entries, skip };
}
