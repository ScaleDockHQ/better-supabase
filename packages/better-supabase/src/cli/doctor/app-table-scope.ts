import type { FindingInput, DoctorContext, Rule } from "./rules.ts";

import {
  hasColumnAccess,
  notNullCheckName,
  scopePolicyName,
  TENANT_SCOPE_NAMES,
  TENANT_SCOPE_POLICY,
} from "../../sql/index.ts";
import { errorText } from "../core/errors.ts";
import { blockDeclaredTables } from "../sql-layout.ts";
import { ident as sqlIdent } from "./live.ts";
import { catalogOf } from "./shared.ts";

const SCHEMA = "public";

const COMMANDS = ["select", "insert", "update", "delete"] as const;

/** An app table with an owner, as the scope rules check it. */
export interface ScopedAppTable {
  readonly name: string;
  readonly scope: "tenant" | "user";
  /** The column that names the owner. */
  readonly column: string;
  /** Whether the app's own schema creates the table, so the entry enriches it. */
  readonly enriched: boolean;
}

/**
 * The app tables whose table the app's own schema creates, so their entries
 * enrich it. Without `sqlFiles`, none.
 */
export function enrichedAppTables(context: DoctorContext): ReadonlySet<string> {
  if (context.sqlFiles === undefined) {
    return new Set();
  }

  const created = blockDeclaredTables(context.sqlFiles, context.config.schemas);

  return new Set(
    Object.keys(context.config.appTables).filter(
      (name) => !created.has(`${SCHEMA}.${name}`),
    ),
  );
}

/** The app tables in `tenant` or `user` scope. */
export function scopedAppTables(context: DoctorContext): ScopedAppTable[] {
  const enriched = enrichedAppTables(context);

  return Object.entries(context.config.appTables).flatMap(
    ([name, config]): ScopedAppTable[] => {
      const scope =
        config.scope === undefined || config.scope === "inherit"
          ? (context.config.sql.scope ?? "tenant")
          : config.scope;

      if (scope === "none") {
        return [];
      }

      return [
        {
          name,
          scope,
          column:
            scope === "user"
              ? "user_id"
              : (context.config.extensions.tenant?.column ?? "organization_id"),
          enriched: enriched.has(name),
        },
      ];
    },
  );
}

const WRITES = ["INSERT", "UPDATE", "DELETE"];

const ROW_PRIVILEGES = new Set(["SELECT", ...WRITES]);

/**
 * The grants an enriched app table holds beyond what its scope grants, for anon
 * and authenticated. Truncate, references and trigger are BS111's.
 */
function broaderGrants(
  context: DoctorContext,
  name: string,
): { readonly grants: readonly string[]; readonly columns: boolean } {
  const config = context.config.appTables[name];

  const table = catalogOf(context).tables.find(
    (entry) => entry.schema === SCHEMA && entry.name === name,
  );

  if (
    config === undefined ||
    table === undefined ||
    context.config.expose[`${SCHEMA}.${name}`] !== undefined ||
    context.config.expose[name] !== undefined
  ) {
    return { grants: [], columns: false };
  }

  const scope =
    config.scope === undefined || config.scope === "inherit"
      ? (context.config.sql.scope ?? "tenant")
      : config.scope;

  const columns = hasColumnAccess(config);

  const allowed = new Set<string>([
    ...(columns ? [] : ["SELECT"]),
    ...(scope === "none" ? [] : columns ? ["DELETE"] : WRITES),
  ]);

  const grants = table.grants.flatMap((grant) =>
    grant.role === "anon" || grant.role === "authenticated"
      ? grant.privileges
          .filter(
            (privilege) =>
              ROW_PRIVILEGES.has(privilege) &&
              (grant.role === "anon" || !allowed.has(privilege)),
          )
          .map((privilege) => `${privilege.toLowerCase()} to ${grant.role}`)
      : [],
  );

  return { grants, columns };
}

/** The `<table>_<column>_not_null` check an enriched table's scope column gets. */
export const scopeCheckName = (table: ScopedAppTable): string =>
  notNullCheckName(
    `${sqlIdent(SCHEMA)}.${sqlIdent(table.name)}`,
    sqlIdent(table.column),
  );

export const APP_TABLE_SCOPE_RULES: readonly Rule[] = [
  {
    code: "BS237",
    severity: "warning",
    title: "App table keeps permissive policies or grants of its own",
    description:
      "An app table in `tenant` or `user` scope has permissive policies next to the ones its scope renders, usually the app's own policies on a table that a `tables.<name>` entry enriches. Postgres ORs permissive policies, so each one widens what the scope allows. In `tenant` scope the restrictive `bsb_tenant_scope` policy still keeps rows inside the member's tenants, so this is a hint (info) to check the roles and permissions those policies skip. In `user` scope, or without `bsb_tenant_scope`, nothing narrows them: a signed-in user reaches every row they allow. Drop the app's policies, or make them restrictive. Enriching never revokes the app's grants either, so the rule also lists the grants anon and authenticated hold on an enriched table beyond what its scope grants: a hint (info) while row level security filters the rows, and a warning when the entry restricts columns (`access` or `encrypted`), since a table-level grant reaches every column.",
    check: (context) => {
      const { tables } = catalogOf(context);

      const grants = [...enrichedAppTables(context)].flatMap(
        (name): FindingInput[] => {
          const broader = broaderGrants(context, name);

          if (broader.grants.length === 0) {
            return [];
          }

          const label = `${SCHEMA}.${name}`;

          return [
            {
              message: broader.columns
                ? `${label} keeps the app's table-level grants (${broader.grants.join(", ")}), which reach the columns tables.${name} restricts. Revoke them in the app's schema; the column grants stay.`
                : `${label} keeps the app's grants beyond its scope (${broader.grants.join(", ")}). Row level security still filters the rows; revoke them in the app's schema if nothing needs them.`,
              ...(broader.columns ? {} : { severity: "info" as const }),
              target: label,
              object: { kind: "table", schema: SCHEMA, name },
            },
          ];
        },
      );

      const policies = scopedAppTables(context).flatMap(
        (app): FindingInput[] => {
          const table = tables.find(
            (entry) => entry.schema === SCHEMA && entry.name === app.name,
          );

          if (table === undefined) {
            return [];
          }

          const own = new Set(
            COMMANDS.map((command) =>
              scopePolicyName(
                { name: app.name, enrich: app.enriched },
                command,
              ),
            ),
          );

          const extra = table.policies.filter(
            (policy) => policy.permissive && !own.has(policy.name),
          );

          if (extra.length === 0) {
            return [];
          }

          const narrowed =
            app.scope === "tenant" &&
            table.policies.some(
              (policy) =>
                !policy.permissive &&
                (policy.name === TENANT_SCOPE_POLICY ||
                  TENANT_SCOPE_NAMES.includes(policy.name)),
            );

          const names = extra.map((policy) => policy.name).join(", ");
          const label = `${SCHEMA}.${app.name}`;

          return [
            {
              message: narrowed
                ? `${label} has permissive policies of its own (${names}). ${TENANT_SCOPE_POLICY} keeps rows inside the member's tenants, but within a tenant these widen what tables.${app.name} allows. Check that they need no role or permission.`
                : `${label} has permissive policies of its own (${names}), and nothing narrows them to the ${app.scope === "user" ? "signed-in user's rows" : "member's tenants"}. Drop them, or make them restrictive.`,
              ...(narrowed ? { severity: "info" as const } : {}),
              target: label,
              object: { kind: "table", schema: SCHEMA, name: app.name },
            },
          ];
        },
      );

      return [...policies, ...grants];
    },
  },
  {
    code: "BS238",
    severity: "warning",
    title: "Rows of an enriched app table without an owner",
    description:
      "A `tables.<name>` entry enriched a table the app already has, and some of its rows have no value in the scope column (`organization_id`, or `user_id` in `user` scope). The scope's policies match no member or user for them, so nobody but the service role reads or writes those rows, and updates to them fail the scope column's `not valid` check. Fill the column with `better-supabase db backfill`, then `doctor --fix` validates the check (BS236). Needs a database; saved snapshots skip it.",
    async check(context) {
      const db = context.database;

      if (!db || "skipped" in db) {
        return [];
      }

      const { tables } = catalogOf(context);
      const findings: FindingInput[] = [];

      for (const app of scopedAppTables(context)) {
        const table = tables.find(
          (entry) => entry.schema === SCHEMA && entry.name === app.name,
        );

        if (
          !app.enriched ||
          !table?.columns.some((column) => column.name === app.column)
        ) {
          continue;
        }

        const label = `${SCHEMA}.${app.name}`;

        const object = {
          kind: "table" as const,
          schema: SCHEMA,
          name: app.name,
        };

        let missing: number;

        try {
          const [row] = await db.query<{ missing: string | number }>(
            `select count(*) as missing from ${sqlIdent(SCHEMA)}.${sqlIdent(app.name)} where ${sqlIdent(app.column)} is null`,
          );

          missing = Number(row?.missing ?? 0);
        } catch (cause) {
          findings.push({
            message: `Could not count the rows of ${label} without ${app.column}: ${errorText(cause)}`,
            target: `${label}.${app.column}`,
            object,
          });
          continue;
        }

        if (missing === 0) {
          continue;
        }

        findings.push({
          message: `${label} has ${missing} ${missing === 1 ? "row" : "rows"} without ${app.column}, which no ${app.scope === "user" ? "user" : "member"} reads or writes, and updates to them fail ${scopeCheckName(app)}. Fill it with \`better-supabase db backfill ${app.name}.${app.column} --from <table.column> via <column>\` (or --value), then run \`better-supabase doctor --fix\`.`,
          target: `${label}.${app.column}`,
          object,
        });
      }

      return findings;
    },
  },
];
