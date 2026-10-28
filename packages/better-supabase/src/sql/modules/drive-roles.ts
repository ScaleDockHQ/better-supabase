import type { BlockSqlContext } from "../context.ts";

import { isRecord } from "../../core/guards.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import { isResourceName, providerRowCheck } from "../provider-rows.ts";

const QUALIFIED = /^[A-Za-z_][\w$]*\.[A-Za-z_][\w$]*$/;

export interface DriveRoleHook {
  readonly label: string;
  readonly role: (id: string, user: string) => string;
}

export interface DriveRoleFunctions {
  readonly node: DriveRoleHook | undefined;
  readonly drive: DriveRoleHook | undefined;
}

function providerRoles(
  ctx: BlockSqlContext,
  all: readonly string[],
  at: string,
  rows: unknown,
  map: unknown,
): DriveRoleHook {
  if (
    !isResourceName(rows) ||
    !isRecord(map) ||
    Object.keys(map).length === 0 ||
    !Object.entries(map).every(
      ([role, key]) =>
        all.includes(role) && typeof key === "string" && key !== "",
    )
  ) {
    throw new TypeError(
      `${at} takes { rows, roles }: the provider's resource name and a permission key for each of options.roles it grants`,
    );
  }

  const checks = all
    .filter((role) => map[role] !== undefined)
    .toReversed()
    .map((role) => ({
      role,
      check: providerRowCheck(ctx, at, rows, String(map[role])),
    }));

  return {
    label: `the authorization provider's grants on ${rows}`,
    role: (id, user) =>
      `case ${checks.map(({ role, check }) => `when ${check(id, user)} then ${sqlString(role)}`).join(" ")} end`,
  };
}

/** `options.roleFunctions`: app functions that return the caller's role. */
export function driveRoleFunctions(
  ctx: BlockSqlContext,
  all: readonly string[],
): DriveRoleFunctions {
  const where = "blocks.drive.options.roleFunctions";
  const raw = ctx.option("roleFunctions");

  if (raw === undefined) {
    return { node: undefined, drive: undefined };
  }

  if (!isRecord(raw)) {
    throw new TypeError(
      `${where} takes { node, drive } function names or { rows, roles }`,
    );
  }

  const parse = (key: "node" | "drive"): DriveRoleHook | undefined => {
    const value = raw[key];

    if (value === undefined) {
      return undefined;
    }

    if (isRecord(value)) {
      return providerRoles(
        ctx,
        all,
        `${where}.${key}`,
        value["rows"],
        value["roles"],
      );
    }

    if (typeof value !== "string" || !QUALIFIED.test(value)) {
      throw new TypeError(
        `${where}.${key} must be a schema-qualified function name, such as public.file_node_role, or { rows, roles }`,
      );
    }

    const fn = value.split(".").map(sqlIdent).join(".");

    return { label: fn, role: (id, user) => `${fn}(${id}, ${user})` };
  };

  return { node: parse("node"), drive: parse("drive") };
}
