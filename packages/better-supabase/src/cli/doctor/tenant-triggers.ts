import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import { moduleLayout, sameTenantColumn } from "../../sql/index.ts";
import { sameTenantLayout } from "../same-tenant-layout.ts";
import { catalogOf, qualified, tableObject } from "./shared.ts";

/** The schema files the app's own triggers are declared in. */
const appFiles = (
  context: DoctorContext,
): readonly { readonly path: string; readonly text: string }[] =>
  (context.sqlFiles ?? []).filter(
    (file) =>
      !file.path.includes("migrations/") &&
      !file.path.includes("better-supabase-data/"),
  );

/**
 * The foreign key columns app triggers declare they guard with `@bsb
 * same-tenant-guard column=...`, by `schema.table`: what `sameTenant.auto`
 * leaves to the app (ADR 1268).
 */
export function appTriggerGuards(
  context: DoctorContext,
): ReadonlyMap<string, ReadonlySet<string>> {
  const columns = sameTenantLayout(
    appFiles(context),
    context.config.schemas,
  ).appTriggerColumns;

  return new Map(
    Object.entries(columns).map(([table, names]) => [table, new Set(names)]),
  );
}

const escape = (name: string): string =>
  name.replaceAll(/[.*+?^${}()|[\]\\]/g, "\\$&");

/**
 * Tenant foreign keys that an app trigger touches but never compares the tenant
 * of.
 */
export const TENANT_TRIGGER_RULES: readonly Rule[] = [
  {
    code: "BS398",
    severity: "warning",
    title: "An app trigger replaces the same-tenant check without the tenant",
    description:
      "`sameTenant.auto` emits no check for a foreign key column that an app trigger (any trigger not named `bsb_*`) declares it guards with `@bsb same-tenant-guard column=<column>` in its function. A trigger that declares the column but never mentions the tenant column guards nothing about the tenant, so the generated check is off and nothing replaces it. Compare the tenant of the referenced row in the trigger, or remove the marker so the block emits the check. Doctor reads the trigger functions in the schema files.",
    check(context) {
      if (!context.config.blockNames.includes("memberships")) {
        return [];
      }

      const tenant = sameTenantColumn(moduleLayout(context.config));
      const guards = appTriggerGuards(context);

      const { appTriggerBodies: bodies } = sameTenantLayout(
        appFiles(context),
        context.config.schemas,
      );

      const mentions = new RegExp(`\\b${escape(tenant)}\\b`, "i");
      const { tables } = catalogOf(context);

      const tenantTables = new Set(
        tables
          .filter((table) =>
            table.columns.some((column) => column.name === tenant),
          )
          .map(qualified),
      );

      return tables
        .filter(
          (table) =>
            context.config.schemas.includes(table.schema) &&
            tenantTables.has(qualified(table)),
        )
        .flatMap((table) => {
          const own = bodies[qualified(table)] ?? [];

          return table.foreignKeys.flatMap((key): FindingInput[] => {
            const [column] = key.columns;

            if (
              column === undefined ||
              key.columns.length !== 1 ||
              column === tenant ||
              !tenantTables.has(`${key.refSchema}.${key.refTable}`) ||
              guards.get(qualified(table))?.has(column) !== true ||
              own.some((body) => mentions.test(body))
            ) {
              return [];
            }

            return [
              {
                message: `${qualified(table)}.${column} references ${key.refSchema}.${key.refTable}, and an app trigger on ${qualified(table)} declares it guards the column, so sameTenant.auto emits no check, but no trigger body mentions ${tenant}. Compare ${tenant} with the referenced row's in the trigger, or remove the @bsb same-tenant-guard marker.`,
                target: `${qualified(table)}.${column}`,
                object: tableObject(table),
              },
            ];
          });
        });
    },
  },
  {
    code: "BS733",
    severity: "info",
    title: "An app trigger turns a generated same-tenant check off",
    description:
      "`sameTenant.auto` emits no `bsb_same_tenant_<column>` check for a foreign key column that an app trigger declares it guards with `@bsb same-tenant-guard column=<column>`. Doctor lists each such column, so a check left to the app is a choice someone made and can review. A trigger that only reads `new.<column>` or `old.<column>` without the marker keeps the generated check (ADR 1268).",
    check(context) {
      if (!context.config.blockNames.includes("memberships")) {
        return [];
      }

      const guards = appTriggerGuards(context);

      return [...guards].flatMap(([table, columns]) =>
        [...columns].map((column) => ({
          message: `${table}.${column}: an app trigger declares @bsb same-tenant-guard, so sameTenant.auto emits no bsb_same_tenant_${column} check and the app's trigger must compare the tenant.`,
          target: `${table}.${column}`,
        })),
      );
    },
  },
];
