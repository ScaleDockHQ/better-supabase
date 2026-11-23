import type { CatalogPolicy, CatalogTable } from "../introspect/types.ts";
import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import { moduleOwned } from "./audit-coverage.ts";
import { BLOCK_PREFIX } from "./block-policies.ts";
import { providerFunctionPatterns } from "./policies.ts";
import { appliesTo, COMMANDS } from "./rls.ts";
import { exposed, qualified, tableObject } from "./shared.ts";

/** Who wrote a policy, so a long list points at the owner. */
export type PolicyOrigin = "library" | "provider" | "app";

/** Library, provider or app: by name, by schema, then by the functions it calls. */
function policyOrigin(
  context: DoctorContext,
): (table: CatalogTable, policy: CatalogPolicy) => PolicyOrigin {
  const owned = moduleOwned(context);

  const provider = providerFunctionPatterns(
    context.config.authorization?.functions,
  );

  return (table, policy) => {
    if (
      policy.name.startsWith(BLOCK_PREFIX) ||
      owned.schemas.has(table.schema) ||
      owned.tables.has(qualified(table))
    ) {
      return "library";
    }

    return (policy.functions ?? []).some((name) =>
      provider.some((pattern) => pattern.test(name)),
    )
      ? "provider"
      : "app";
  };
}

/** The policies Postgres evaluates for `authenticated` on one command. */
function forCommand(
  table: CatalogTable,
  command: (typeof COMMANDS)[number],
): CatalogPolicy[] {
  return table.policies.filter(
    (policy) =>
      (policy.command === "all" || policy.command === command) &&
      appliesTo(policy, "authenticated"),
  );
}

export const POLICY_COUNT_RULES: readonly Rule[] = [
  {
    code: "BS641",
    severity: "info",
    title: "Many policies for one command",
    description:
      "Postgres evaluates every permissive policy (or-ed) and every restrictive policy (and-ed) of a command for each row it reads or writes, so each extra policy adds a condition to every query on the table. One finding per table and command with more than `doctor.policies.max` policies for `authenticated` (default 4), listing each policy with its kind and origin: library (`bsb_` policies and block tables), provider (calls a function of the authorization provider) or app. Fold the provider or app policies the list names into fewer conditions; the library's own policies are one restrictive guard and one permissive grant per command.",
    check: (context) => {
      const max = context.config.doctor.policies.max;
      const origin = policyOrigin(context);

      return exposed(context).flatMap((table) => {
        if (!table.rls || table.kind !== "table") {
          return [];
        }

        return COMMANDS.flatMap((command): FindingInput[] => {
          const policies = forCommand(table, command);

          if (policies.length <= max) {
            return [];
          }

          const listed = policies
            .map(
              (policy) =>
                `${policy.name} (${policy.permissive ? "permissive" : "restrictive"}, ${origin(table, policy)})`,
            )
            .join(", ");

          return [
            {
              message: `${qualified(table)} has ${String(policies.length)} ${command} policies for authenticated, more than doctor.policies.max (${String(max)}): ${listed}.`,
              target: `${qualified(table)}.${command}`,
              object: tableObject(table),
            },
          ];
        });
      });
    },
  },
  {
    code: "BS642",
    severity: "info",
    title: "Index leads with an enum column on an RLS table",
    description:
      "Postgres marks `enum_eq` as not leakproof, so on a table with RLS it may not use a condition on an enum column as an index condition before the policies have passed; `where status = 'open'` then filters after a wider scan. `text` (`texteq`) and `uuid` comparisons are leakproof. Store the value as `text` with a `check (status in (...))` constraint, the way every block does. Marking `enum_eq` leakproof needs a superuser, so the library doesn't.",
    check: (context) =>
      exposed(context).flatMap((table) => {
        if (!table.rls || table.kind !== "table") {
          return [];
        }

        const enums = new Set(
          table.columns
            .filter((column) => column.isEnum && !column.isArray)
            .map((column) => column.name),
        );

        return table.indexes.flatMap((index): FindingInput[] => {
          const lead = index.columns[0];

          if (lead === undefined || !enums.has(lead)) {
            return [];
          }

          return [
            {
              message: `Index ${index.name} on ${qualified(table)} leads with the enum column ${lead}. Under RLS a condition on it can't use the index before the policies pass, because enum_eq isn't leakproof. Make ${lead} text with a check constraint.`,
              target: `${qualified(table)}.${index.name}`,
              object: tableObject(table),
            },
          ];
        });
      }),
  },
];
