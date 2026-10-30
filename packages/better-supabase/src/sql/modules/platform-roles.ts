import type { BlockSqlContext } from "../context.ts";

import { sqlIdent } from "../../core/template.ts";
import { accessModel } from "./permissions-model.ts";

/**
 * `blocks.invitations.options.platformRoles` under the `provider` model: the
 * app's table of platform role assignments, so platform invitations insert into
 * it.
 */
export interface ProviderPlatformRoles {
  /** Quoted `schema.table`. */
  readonly table: string;
  /** Quoted columns. */
  readonly user: string;
  readonly role: string;
  /** The roles table the role column points into, quoted. */
  readonly through?: {
    readonly table: string;
    readonly id: string;
    readonly column: string;
    /** A condition on the roles row `{row}` that holds for platform roles only. */
    readonly where?: string;
  };
  /**
   * A SQL template with `{user}` and `{role}` (the role name) deciding who
   * assigns which platform role.
   */
  readonly canAssign?: string;
  readonly canAssignFor?: string;
}

const isPlain = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const quotedRef = (where: string, table: string, column: string) => {
  const parts = `${table}.${column}`.split(".");

  if (
    parts.length !== 3 ||
    parts.some((part) => !/^[A-Za-z_][A-Za-z0-9_$]*$/.test(part))
  ) {
    throw new TypeError(
      `${where}: "${table}" must be "schema.table" and "${column}" a column`,
    );
  }

  return {
    table: `${sqlIdent(parts[0]!)}.${sqlIdent(parts[1]!)}`,
    column: sqlIdent(parts[2]!),
  };
};

/** The `provider` model's platform role table, or `undefined` without one. */
export function providerPlatformRoles(
  ctx: BlockSqlContext,
): ProviderPlatformRoles | undefined {
  if (accessModel(ctx) !== "provider" || !ctx.installed("invitations")) {
    return undefined;
  }

  const value = ctx.of("invitations").option("platformRoles");

  if (value === undefined) {
    return undefined;
  }

  const where = "blocks.invitations.options.platformRoles";

  if (
    !isPlain(value) ||
    typeof value["table"] !== "string" ||
    typeof value["user"] !== "string" ||
    typeof value["role"] !== "string" ||
    (value["canAssign"] !== undefined &&
      typeof value["canAssign"] !== "string") ||
    (value["canAssignFor"] !== undefined &&
      (typeof value["canAssignFor"] !== "string" ||
        !value["canAssignFor"].includes("{user}")))
  ) {
    throw new TypeError(
      `${where} must be { table: "schema.table", user: "<user column>", role: "<role column>", through?: { table, id, column }, canAssign?: "<SQL template>", canAssignFor?: "<SQL template with {user}>" }`,
    );
  }

  const user = quotedRef(where, value["table"], value["user"]);
  const role = quotedRef(where, value["table"], value["role"]);
  const through = value["through"];
  let lookup: ProviderPlatformRoles["through"];

  if (through !== undefined) {
    if (
      !isPlain(through) ||
      typeof through["table"] !== "string" ||
      typeof through["id"] !== "string" ||
      typeof through["column"] !== "string" ||
      (through["where"] !== undefined &&
        (typeof through["where"] !== "string" ||
          !through["where"].includes("{row}")))
    ) {
      throw new TypeError(
        `${where}.through must be { table: "schema.table", id: "<key column>", column: "<role name column>", where?: "<condition on {row}>" }`,
      );
    }

    const id = quotedRef(`${where}.through`, through["table"], through["id"]);
    lookup = {
      table: id.table,
      id: id.column,
      column: quotedRef(`${where}.through`, through["table"], through["column"])
        .column,
      ...(typeof through["where"] === "string"
        ? { where: through["where"] }
        : {}),
    };
  }

  return {
    table: user.table,
    user: user.column,
    role: role.column,
    ...(lookup ? { through: lookup } : {}),
    ...(typeof value["canAssign"] === "string"
      ? { canAssign: value["canAssign"] }
      : {}),
    ...(typeof value["canAssignFor"] === "string"
      ? { canAssignFor: value["canAssignFor"] }
      : {}),
  };
}

/** Whether the catalog has platform roles, and so platform invitations. */
export function hasPlatformRoles(ctx: BlockSqlContext): boolean {
  if (providerPlatformRoles(ctx)) {
    return true;
  }

  return (
    accessModel(ctx) === "catalog" &&
    ctx.of("permissions").hasTable("platformAssignments")
  );
}
