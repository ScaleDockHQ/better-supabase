import type { Rule } from "./rules.ts";

import {
  catalogOf,
  exposed,
  policyObject,
  qualified,
  tableObject,
} from "./shared.ts";

const MFA_FACTORS = /\bauth\.\s*"?mfa_factors\b/i;

/** Rules about what policies and foreign keys do with `auth` tables. */
export const AUTH_USER_RULES: readonly Rule[] = [
  {
    code: "BS108",
    severity: "error",
    title: "Policy reads auth.mfa_factors directly",
    description:
      "`authenticated` has no access to `auth.mfa_factors`, so a policy that reads it fails every request with 42501. Check the factor in a `security definer` function such as `better_supabase.mfa_satisfied()` from the `mfa` SQL module.",
    check: (context) =>
      exposed(context).flatMap((table) =>
        table.policies
          .filter((policy) =>
            MFA_FACTORS.test(`${policy.using ?? ""} ${policy.check ?? ""}`),
          )
          .map((policy) => ({
            message: `Policy "${policy.name}" on ${qualified(table)} reads auth.mfa_factors, which authenticated can't select, so every request fails with 42501. Use \`(select better_supabase.mfa_satisfied())\` from \`better-supabase add mfa\` instead.`,
            target: `${qualified(table)}.${policy.name}`,
            object: policyObject(table, policy),
          })),
      ),
  },
  {
    code: "BS406",
    severity: "warning",
    title: "Foreign key to auth.users blocks account deletion",
    description:
      'A foreign key to `auth.users` with `no action` or `restrict` makes `auth.admin.deleteUser` (and `deleteAccount`) fail with "Database error deleting user" while the user has rows. Use `on delete cascade` for data the user owns, or `on delete set null` for records that outlive them.',
    check: (context) =>
      catalogOf(context).tables.flatMap((table) =>
        table.schema === "auth"
          ? []
          : table.foreignKeys
              .filter(
                (key) =>
                  key.refSchema === "auth" &&
                  key.refTable === "users" &&
                  (key.onDelete === "no action" || key.onDelete === "restrict"),
              )
              .map((key) => ({
                message: `${qualified(table)}.${key.name} (${key.columns.join(", ")}) references auth.users with on delete ${key.onDelete}. Deleting the user fails while rows point at it; use on delete cascade or set null.`,
                target: `${qualified(table)}.${key.name}`,
                object: tableObject(table),
              })),
      ),
  },
];
