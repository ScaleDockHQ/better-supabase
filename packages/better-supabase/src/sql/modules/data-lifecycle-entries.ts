import type { ModuleContext } from "../context.ts";

import { sqlIdent } from "../../core/template.ts";
import { columnRef } from "../shared.ts";
import { exportOmits } from "./data-lifecycle-credentials.ts";

/** An app table in `options.tables`: its user and tenant columns. */
export interface LifecycleTable {
  /** The column holding the user id, for user exports. */
  readonly user?: string;
  /** The tenant column, for organization exports and the purge. */
  readonly tenant?: string;
  /** Delete its tenant rows in the purge. Default true. */
  readonly purge?: boolean;
  readonly omit?: readonly string[];
  readonly export?: boolean;
}

/** One table an export reads or the purge clears. */
interface Entry {
  readonly subject: "user" | "organization";
  /** `schema.table`, unquoted, for file names. */
  readonly name: string;
  /** Quoted, for `to_regclass`. */
  readonly table: string;
  /** Unquoted, for `%I`. */
  readonly column: string;
  readonly purge: boolean;
  readonly omit: readonly string[];
  readonly export: boolean;
}

/** A Storage bucket id: Supabase allows 1 to 100 characters. */
const BUCKET = /^[a-z0-9][a-z0-9_.-]{0,99}$/;

const IDENT = /^[a-z_][a-z0-9_$]{0,62}$/;

function unquoted(ctx: ModuleContext, logical: string): string {
  const { schema, name } = ctx.tableName(logical);
  return `${schema}.${name}`;
}

/** The tables each installed module contributes, then `options.tables`. */
export function entries(ctx: ModuleContext): readonly Entry[] {
  const list: Entry[] = [];
  const modules = ctx.installedModules.map((module) => ctx.of(module));
  for (const subject of ["user", "organization"] as const) {
    for (const of of modules) {
      for (const [logical, spec] of Object.entries(of.names.tables)) {
        const column =
          subject === "user" ? spec.lifecycle?.user : spec.lifecycle?.tenant;
        if (column === undefined) {
          continue;
        }
        if (!of.hasTable(logical) || !of.has(logical, column)) {
          continue;
        }
        list.push({
          subject,
          name: unquoted(of, logical),
          table: of.table(logical),
          column: of.col(logical, column).replaceAll('"', ""),
          purge: spec.lifecycle?.purge !== false,
          export: spec.lifecycle?.export !== false,
          omit: exportOmits(spec.lifecycle)
            .filter((name) => of.has(logical, name))
            .map((name) => of.col(logical, name).replaceAll('"', "")),
        });
      }
    }
  }

  const where = "blocks.data-lifecycle.options.tables";
  const option = ctx.option("tables");
  if (option === undefined || option === "auto") {
    return list;
  }
  const configured: Entry[] = [];
  if (typeof option !== "object" || option === null || Array.isArray(option)) {
    throw new TypeError(
      `${where} must be an object of table names to { user, tenant, purge }`,
    );
  }
  for (const [key, value] of Object.entries(option)) {
    const parts = key.split(".");
    if (parts.length > 2 || !parts.every((part) => IDENT.test(part))) {
      throw new TypeError(
        `${where}: "${key}" must be "table" or "schema.table"`,
      );
    }
    const [schema = "public", table = key] =
      parts.length === 2 ? parts : ["public", key];
    if (typeof value !== "object" || value === null || Array.isArray(value)) {
      throw new TypeError(`${where}.${key} must be an object`);
    }
    // SAFETY: an object, and each field is checked below.
    const config = value as LifecycleTable;
    for (const column of [config.user, config.tenant]) {
      if (
        column !== undefined &&
        (typeof column !== "string" || !IDENT.test(column))
      ) {
        throw new TypeError(
          `${where}.${key}: column names must be lowercase identifiers`,
        );
      }
    }
    const omit: unknown = config.omit ?? [];
    if (
      !Array.isArray(omit) ||
      !omit.every((name) => typeof name === "string" && IDENT.test(name))
    ) {
      throw new TypeError(
        `${where}.${key}.omit must be a list of lowercase column names`,
      );
    }
    if (config.export !== undefined && typeof config.export !== "boolean") {
      throw new TypeError(`${where}.${key}.export must be true or false`);
    }
    if (config.user === undefined && config.tenant === undefined) {
      throw new TypeError(`${where}.${key} needs a user or a tenant column`);
    }
    const base = {
      name: `${schema}.${table}`,
      table: `${sqlIdent(schema)}.${sqlIdent(table)}`,
      purge: config.purge !== false,
      export: config.export !== false,
      omit: omit.filter((name) => typeof name === "string"),
    };
    if (config.user !== undefined) {
      configured.push({ ...base, subject: "user", column: config.user });
    }
    if (config.tenant !== undefined) {
      configured.push({
        ...base,
        subject: "organization",
        column: config.tenant,
      });
    }
  }
  const replaced = new Set(configured.map((entry) => entry.name));
  return [...list.filter((entry) => !replaced.has(entry.name)), ...configured];
}

export function bucketOf(ctx: ModuleContext): string {
  const bucket = ctx.text("bucket", "data-exports");
  if (!BUCKET.test(bucket)) {
    throw new TypeError(
      "blocks.data-lifecycle.options.bucket must be 1 to 100 lowercase letters, digits, dots, dashes or underscores",
    );
  }
  return bucket;
}

/**
 * The tenant's own row the purge deletes last: `options.tenantRow`
 * (`schema.table.column`, `false` for none), else the organizations module's
 * table, else the table the access contract disables tenants in.
 */
export function tenantRowOf(
  ctx: ModuleContext,
): { readonly table: string; readonly key: string } | undefined {
  const configured = ctx.option("tenantRow");
  if (configured === false) {
    return undefined;
  }
  if (configured !== undefined) {
    if (typeof configured !== "string") {
      throw new TypeError(
        'blocks.data-lifecycle.options.tenantRow must be "schema.table.column" or false',
      );
    }
    const ref = columnRef(
      "blocks.data-lifecycle.options.tenantRow",
      configured,
    );
    return { table: ref.table, key: ref.column };
  }
  if (ctx.installed("organizations")) {
    const organizations = ctx.of("organizations");
    return {
      table: organizations.table("organizations"),
      key: organizations.col("organizations", "id"),
    };
  }
  const disable = disabling(ctx);
  return disable ? { table: disable.table, key: disable.key } : undefined;
}

/** The statement that disables a tenant, from the access contract. */
export function disabling(
  ctx: ModuleContext,
): { table: string; key: string; column: string } | undefined {
  const configured = ctx.modules.access?.disabled?.tenant;
  if (typeof configured === "string") {
    const ref = columnRef("blocks.access.disabled.tenant", configured);
    return { table: ref.table, key: '"id"', column: ref.column };
  }
  if (configured) {
    if (configured.disabledAt === undefined) {
      return undefined;
    }
    return {
      table: configured.table
        .split(".")
        .map((part) => sqlIdent(part))
        .join("."),
      key: sqlIdent(configured.id),
      column: sqlIdent(configured.disabledAt),
    };
  }
  if (!ctx.installed("organizations")) {
    return undefined;
  }
  const organizations = ctx.of("organizations");
  if (
    !organizations.manages ||
    !organizations.has("organizations", "disabledAt")
  ) {
    return undefined;
  }
  return {
    table: organizations.table("organizations"),
    key: organizations.col("organizations", "id"),
    column: organizations.col("organizations", "disabledAt"),
  };
}
