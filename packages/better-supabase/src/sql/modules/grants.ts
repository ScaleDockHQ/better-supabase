import type { BlockSqlLayout, BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import { hasColumnExclusions } from "../expose-columns.ts";
import { quotedTable } from "../shared.ts";

export const GRANTS: BlockSqlDefinition = {
  name: "grants",
  names: { tables: {}, options: ["fromPolicies"] },
  title: "Data API grants",
  description:
    "Writes the complete Data API privileges of the tables and functions in the `expose` config for anon, authenticated and service_role, or derives table grants from the policies. A project with default privileges turned off grants new tables to no Data API role.",
  requires: [],
  target: "schema",
  build:
    () => `-- List tables and functions in \`expose\` (better-supabase.config.ts); \`upgrade\` rewrites the grants below.
-- Each listed table or function gets exactly the listed privileges: the rest is revoked.
-- RLS still decides which rows each role sees; grants decide whether the role reaches the table at all.`,
  extras: (_ctx, layout) => tableGrants(layout),
};

/** Privileges one role gets on a table or view. */
export interface TableGrant {
  /** `table` or `schema.table`. */
  readonly table: string;
  readonly role: "anon" | "authenticated" | "service_role";
  readonly privileges: readonly string[];
}

const privilegeSql = (privilege: string): string => {
  const open = privilege.indexOf("(");

  if (open === -1) {
    return privilege;
  }

  if (hasColumnExclusions(privilege)) {
    throw new TypeError(
      `expose: "${privilege}" resolves against the declared columns, which \`upgrade\` reads from the schema files. Run \`better-supabase upgrade\`, or list the columns.`,
    );
  }

  const columns = privilege
    .slice(open + 1, privilege.lastIndexOf(")"))
    .split(",")
    .map((column) => sqlIdent(column.trim()));

  return `${privilege.slice(0, open).trim()} (${columns.join(", ")})`;
};

/** The roles that may execute a function. */
export interface FunctionGrant {
  /** `name(argument types)` or `schema.name(argument types)`. */
  readonly function: string;
  readonly roles: readonly ("anon" | "authenticated" | "service_role")[];
}

export const qualifiedTable = (name: string): string => quotedTable(name);

function qualifiedFunction(signature: string): string {
  const open = signature.indexOf("(");
  const name = signature.slice(0, open).trim();
  const args = signature.slice(open);

  if (open <= 0 || !/^\([\w\s,.[\]"]*\)$/.test(args)) {
    throw new TypeError(
      `expose: "${signature}" is not a function signature such as search_notes(text, integer)`,
    );
  }

  return `${qualifiedTable(name)}${args}`;
}

const keyOf = (name: string): string =>
  name.includes(".") ? name : `public.${name}`;

/**
 * Each listed table's complete privilege set: everything is revoked from the
 * API roles first, then the listed privileges are granted. Policy grants fill
 * tables `expose` doesn't list, with every privilege for `service_role`. With
 * policy grants on, a declared table that `expose` doesn't list, with RLS on
 * and no permissive policy reaching it, is service-only. Not `lockTable`: this
 * also revokes from `public` and `service_role`, and leaves RLS to the module
 * that declares the table.
 */
function tableGrants(layout: BlockSqlLayout): string {
  const listed = layout.grants ?? [];
  const named = new Set(listed.map((grant) => keyOf(grant.table)));

  const derived = (layout.policyGrants ?? []).filter(
    (grant) => !named.has(keyOf(grant.table)),
  );

  const derivedTables = [...new Set(derived.map((grant) => grant.table))];

  const reached = new Set(
    (layout.policyGrants ?? []).map((grant) => keyOf(grant.table)),
  );

  const serviceOnly =
    layout.policyGrants === undefined
      ? []
      : (layout.declaredTables ?? []).filter(
          (table) =>
            (layout.rlsTables ?? []).includes(table) &&
            !named.has(keyOf(table)) &&
            !reached.has(keyOf(table)),
        );

  const grants = [
    ...listed,
    ...derived,
    ...[...derivedTables, ...serviceOnly].map((table): TableGrant => ({
      table,
      role: "service_role",
      privileges: ["select", "insert", "update", "delete"],
    })),
  ];

  const tables = [...new Set(grants.map((grant) => keyOf(grant.table)))];

  const statements = tables.flatMap((table) => [
    `revoke all on table ${qualifiedTable(table)} from public, anon, authenticated, service_role;`,
    ...grants
      .filter(
        (grant) => keyOf(grant.table) === table && grant.privileges.length > 0,
      )
      .map(
        (grant) =>
          `grant ${grant.privileges.map(privilegeSql).join(", ")} on table ${qualifiedTable(table)} to ${grant.role};`,
      ),
  ]);

  const functions = (layout.functionGrants ?? []).flatMap((grant) => {
    const target = qualifiedFunction(grant.function);

    return [
      `revoke execute on function ${target} from public, anon, authenticated, service_role;`,
      ...(grant.roles.length > 0
        ? [`grant execute on function ${target} to ${grant.roles.join(", ")};`]
        : []),
    ];
  });

  const all = [...statements, ...functions];

  if (all.length === 0) {
    return "";
  }

  return `\n-- config.expose${derived.length > 0 || serviceOnly.length > 0 ? " and the policies (blocks['grants'].options.fromPolicies)" : ""}\n${all.join("\n")}\n`;
}
