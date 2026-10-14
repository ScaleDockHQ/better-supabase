import type { ResolvedConfig } from "../../config/index.ts";
import type { CommandResult } from "../io.ts";
import type { Now } from "./migrations.ts";

import { resolveModules, SQL_MODULES } from "../../sql/index.ts";
import { providerLabel } from "../authorization.ts";
import { type SqlFlags, USAGE } from "./args.ts";
import {
  layoutFor,
  MEMBERSHIP_CLAIM_MODULES,
  providerOwnsMemberships,
} from "./providers.ts";
import { nextStep, unlistedModuleFiles, write } from "./write.ts";

export async function addModules(
  config: ResolvedConfig,
  args: SqlFlags,
  names: readonly string[],
  now: Now,
): Promise<CommandResult> {
  if (names.length === 0) {
    return { code: 2, error: `Name at least one module.\n${USAGE}` };
  }
  const unknown = names.filter((name) => !(name in SQL_MODULES));
  if (unknown.length > 0) {
    return {
      code: 2,
      error: `Unknown module ${unknown.join(", ")}. Available: ${Object.keys(SQL_MODULES).join(", ")}`,
    };
  }
  const owner =
    config.authorization && providerOwnsMemberships(config)
      ? providerLabel(config.authorization)
      : undefined;
  const hookModules = names.filter((name) =>
    MEMBERSHIP_CLAIM_MODULES.has(name),
  );
  if (owner && hookModules.length > 0 && args.force !== true) {
    return {
      code: 1,
      error: [
        `The access token hook of ${owner} writes the memberships claim.`,
        `${hookModules.join(" and ")} would add a second source for it. Use the provider's hook instead,`,
        "or pass --force to write the modules anyway.",
      ].join("\n"),
    };
  }
  // Render with the modules sql.modules already lists, so the new ones
  // see them (a foreign key to the organizations table, plan quotas
  // over entitlements), but write only the named ones and what they need.
  const listed = [
    ...config.sql.moduleNames,
    ...names.filter((name) => !config.sql.moduleNames.includes(name)),
  ];
  const sqlLayout = await layoutFor(config, args, listed);
  const added = resolveModules(names, sqlLayout).map((module) => module.name);
  const lines = await write(config, args, listed, sqlLayout, now, added);
  const pulledIn = resolveModules(names, sqlLayout)
    .map((module) => module.name)
    .filter(
      (name) => MEMBERSHIP_CLAIM_MODULES.has(name) && !names.includes(name),
    );
  if (owner && pulledIn.length > 0) {
    lines.push(
      "",
      `${pulledIn.join(" and ")} came along as a dependency: its memberships table backs has_organization_role() and has_entitlement().`,
      `The hook of ${owner} still writes the memberships claim, so don't call better_supabase.membership_claims from a hook.`,
      "Make better_supabase.memberships one of the provider's membership sources if both should agree.",
    );
  }
  const untracked = resolveModules(names, sqlLayout)
    .map((module) => module.name)
    .filter((name) => !config.sql.moduleNames.includes(name));
  if (untracked.length > 0) {
    lines.push(
      "",
      `Add them to your config so \`sql sync --check\` keeps them current:`,
      `  sql: { modules: [${[...config.sql.moduleNames, ...untracked].map((name) => `'${name}'`).join(", ")}] }`,
    );
  }
  if (args["dry-run"] !== true)
    lines.push(...(await unlistedModuleFiles(config, names, sqlLayout)));
  lines.push("", await nextStep(config));
  return { code: 0, output: lines.join("\n") };
}
