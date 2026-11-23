import type { DoctorContext, FindingInput } from "./rules.ts";

import { tenantNameOf } from "../../config/index.ts";
import { providerLabel } from "../authorization.ts";
import { providerCalls } from "./provider-calls.ts";
import {
  appliesTo,
  pinnedToTenant,
  tenantPins,
  withoutStrings,
} from "./rls.ts";
import { catalogOf, policyObject, qualified } from "./shared.ts";

const CALLER_ROW =
  /\bauth\.(?:uid|jwt|email)\s*\(|better_supabase\.current_user_id\s*\(|\bcurrent_user\b/i;

/**
 * The provider's `tables` entries that its select policies contradict: a
 * `tenant` table whose policies also filter by the caller's row, and a table
 * whose policies check other keys than its `permissions`.
 */
export function tableShares(context: DoctorContext): FindingInput[] {
  const provider = context.config.authorization;
  const declared = Object.entries(provider?.tables ?? {});

  if (!provider || declared.length === 0) {
    return [];
  }

  const findings: FindingInput[] = [];
  const pins = tenantPins(context);

  const tenantColumn =
    context.config.sql.tenantColumn ??
    `${tenantNameOf(context.config.blocks) ?? "organization"}_id`;

  const tables = catalogOf(context).tables;

  for (const [name, entry] of declared) {
    const target = `authorization.tables.${name}`;

    const table = tables.find(
      (candidate) => candidate.name === name || qualified(candidate) === name,
    );

    if (!table) {
      findings.push({
        message: `${providerLabel(provider)} declares ${name} in tables, but the database has no such table.`,
        target,
      });
      continue;
    }

    const selects = table.policies.filter(
      (policy) =>
        policy.permissive &&
        (policy.command === "all" || policy.command === "select") &&
        appliesTo(policy, "authenticated"),
    );

    const checked = new Set(
      selects.flatMap((policy) =>
        providerCalls(provider, policy.using ?? "")
          .filter((call) => call.scope !== "platform")
          .map((call) => call.key),
      ),
    );

    const listed = new Set<string>(entry.permissions);

    const differs =
      checked.size !== listed.size ||
      [...checked].some((key) => !listed.has(key));

    if (differs) {
      findings.push({
        message: `${providerLabel(provider)} declares ${qualified(table)} with permissions [${[...listed].join(", ")}], but its select policies check [${[...checked].join(", ")}]. A shared entry would be keyed on the wrong grant; make the two lists match.`,
        target,
      });
    }

    if (entry.share !== "tenant") {
      continue;
    }

    const rowLevel = selects.filter((policy) =>
      CALLER_ROW.test(withoutStrings(policy.using ?? "")),
    );

    if (
      rowLevel.length > 0 ||
      !pinnedToTenant(table, tenantColumn, "select", "authenticated", pins)
    ) {
      const named =
        rowLevel.length > 0
          ? `policy ${rowLevel.map((policy) => `"${policy.name}"`).join(", ")} filters by the caller`
          : `its select policies don't pin ${tenantColumn} to a tenant the caller acts in`;

      const policy = rowLevel[0] ?? selects[0];

      findings.push({
        message: `${providerLabel(provider)} declares ${qualified(table)} as share: "tenant", but ${named}. Two callers with the same grant could read different rows, so a shared cache entry would leak one caller's rows to the other. Declare it share: "row".`,
        target,
        ...(policy ? { object: policyObject(table, policy) } : {}),
      });
    }
  }

  return findings;
}
