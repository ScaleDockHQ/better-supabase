import { readFile } from "node:fs/promises";
import { basename, dirname } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { SqlDeps } from "../commands/sql.ts";
import type { CommandResult } from "../core/io.ts";
import type { SqlFlags } from "./args.ts";

import { resolveBlocks, SQL_MODULES } from "../../sql/index.ts";
import { providerLabel } from "../authorization.ts";
import { CliError } from "../core/errors.ts";
import { applyPlan } from "../core/files.ts";
import { addBlocksToConfig, addBlocksToJson, keyText } from "./config-edit.ts";
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
  deps: SqlDeps,
): Promise<CommandResult> {
  if (names.length === 0) {
    throw new CliError("input_required", "Name at least one module.", {
      missing: ["<module>"],
      choices: { "<module>": Object.keys(SQL_MODULES) },
    });
  }

  const unknown = names.filter((name) => !(name in SQL_MODULES));

  if (unknown.length > 0) {
    throw new CliError(
      "usage",
      `Unknown module ${unknown.join(", ")}. Available: ${Object.keys(SQL_MODULES).join(", ")}`,
    );
  }

  const owner =
    config.authorization && providerOwnsMemberships(config)
      ? providerLabel(config.authorization)
      : undefined;

  const hookModules = names.filter((name) =>
    MEMBERSHIP_CLAIM_MODULES.has(name),
  );

  if (owner && hookModules.length > 0 && args["allow-hook-overlap"] !== true) {
    return {
      code: 1,
      error: [
        `The access token hook of ${owner} writes the memberships claim.`,
        `${hookModules.join(" and ")} would add a second source for it. Use the provider's hook instead,`,
        "or pass --allow-hook-overlap to write the modules anyway.",
      ].join("\n"),
    };
  }

  // Render with the modules blocks already lists, so the new ones
  // see them (a foreign key to the organizations table, plan quotas
  // over entitlements), but write only the named ones and what they need.
  const listed = [
    ...config.blockNames,
    ...names.filter((name) => !config.blockNames.includes(name)),
  ];

  const sqlLayout = await layoutFor(config, args, listed);
  const added = resolveBlocks(names, sqlLayout).map((module) => module.name);
  const lines = await write(config, args, listed, sqlLayout, deps.now, added);

  const pulledIn = resolveBlocks(names, sqlLayout)
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

  const untracked = resolveBlocks(names, sqlLayout)
    .map((module) => module.name)
    .filter((name) => !config.blockNames.includes(name));

  if (untracked.length > 0) {
    lines.push("", ...(await listInConfig(args, untracked, deps)));
  }

  if (args["dry-run"] !== true) {
    lines.push(...(await unlistedModuleFiles(config, names, sqlLayout)));
  }

  return {
    code: 0,
    output: lines.join("\n"),
    data: { added, pulledIn, untracked },
    next: [await nextStep(config)],
  };
}

/**
 * Lists `untracked` in `blocks` of the config file, so `sql sync --check` keeps
 * them current, or prints the snippet when the file isn't a literal object the
 * edit can follow.
 */
async function listInConfig(
  args: SqlFlags,
  untracked: readonly string[],
  deps: SqlDeps,
): Promise<string[]> {
  const file = deps.configFile;

  if (file === undefined) {
    return [
      "Add them to blocks in better-supabase.config.ts so `sql sync --check` keeps them current:",
      ...untracked.map((name) => `  ${keyText(name)}: {},`),
    ];
  }

  const source = await readFile(file, "utf-8");

  const edit = file.endsWith(".json")
    ? addBlocksToJson(source, untracked)
    : addBlocksToConfig(source, untracked);

  if (!edit.ok) {
    return [
      `${basename(file)} wasn't changed: ${edit.reason}.`,
      "Add them to blocks so `sql sync --check` keeps them current:",
      ...untracked.map((name) => `  ${keyText(name)}: {},`),
    ];
  }

  await applyPlan(
    {
      root: dirname(file),
      regenerate: "better-supabase sql add",
      files: [{ path: file, contents: edit.text, policy: "edit" }],
    },
    { "dry-run": args["dry-run"] },
  );

  if (args["dry-run"] === true) {
    return [
      `Would add ${untracked.join(", ")} to blocks in ${basename(file)}.`,
    ];
  }

  return [`Added ${untracked.join(", ")} to blocks in ${basename(file)}.`];
}
