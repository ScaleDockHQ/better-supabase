import { readFile } from "node:fs/promises";
import { basename, dirname } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { SqlDeps } from "../commands/sql.ts";
import type { CommandResult } from "../core/io.ts";
import type { SqlFlags } from "./args.ts";

import {
  DEFAULT_CONVENTIONS,
  PRESET_CATALOG,
  resolvePreset,
} from "../../preset/index.ts";
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

/**
 * True for a block made of other blocks, which `add` lists in `blocks` by its
 * own name.
 */
export function isComposite(name: string): boolean {
  return PRESET_CATALOG.manifests.some(
    (manifest) =>
      manifest.name === name && Object.keys(manifest.composes ?? {}).length > 0,
  );
}

/**
 * Writes the modules behind `requested`. A composite stands for the modules of
 * its parts; the config lists the composite, not each part.
 */
export async function addModules(
  config: ResolvedConfig,
  args: SqlFlags,
  requested: readonly string[],
  deps: SqlDeps,
): Promise<CommandResult> {
  const composites = requested.filter(isComposite);

  const expanded =
    composites.length === 0
      ? []
      : resolvePreset({
          ...DEFAULT_CONVENTIONS,
          blocks: composites,
        }).blocks.map((block) => block.name);

  const names = [
    ...new Set([
      ...requested.filter((name) => !composites.includes(name)),
      ...expanded,
    ]),
  ];

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

  const withAdded = withAddedBlocks(config, names);
  const sqlLayout = await layoutFor(withAdded, args, listed);
  const added = resolveBlocks(names, sqlLayout).map((module) => module.name);
  const affected = integratingModules(config.blockNames, added);

  const written = await write(withAdded, args, listed, sqlLayout, deps.now, [
    ...added,
    ...affected.map((entry) => entry.name),
  ]);

  const lines = [...written.lines];

  if (affected.length > 0) {
    lines.push(
      "",
      ...affected.map(
        (entry) =>
          `Re-rendered ${entry.name}: it integrates with ${entry.with.join(", ")}.`,
      ),
    );
  }

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

  const untracked = [
    ...composites,
    ...resolveBlocks(names, sqlLayout)
      .map((module) => module.name)
      .filter((name) => !expanded.includes(name)),
  ].filter(
    (name, index, all) =>
      !config.blockNames.includes(name) && all.indexOf(name) === index,
  );

  if (untracked.length > 0) {
    lines.push("", ...(await listInConfig(args, untracked, deps)));
  }

  if (args["dry-run"] !== true) {
    lines.push(...(await unlistedModuleFiles(withAdded, names, sqlLayout)));
  }

  return {
    code: written.error === undefined ? 0 : 1,
    output: lines.join("\n"),
    ...(written.error === undefined
      ? {}
      : { error: written.error, errorCode: "file_conflict" as const }),
    data: { added, pulledIn, untracked },
    next: [await nextStep(config)],
  };
}

/**
 * The installed modules whose SQL changes now that `added` is installed: the
 * ones that integrate with one of them, so their files render the joins again
 * (entitlements reads plan quotas once billing is installed).
 */
export function integratingModules(
  installed: readonly string[],
  added: readonly string[],
): { name: string; with: string[] }[] {
  const fresh = new Set(added.filter((name) => !installed.includes(name)));

  return installed.flatMap((name) => {
    const definition = SQL_MODULES[name];

    if (definition === undefined || fresh.has(name)) {
      return [];
    }

    const touched = (definition.integrates ?? []).filter((each) =>
      fresh.has(each),
    );

    return touched.length === 0 ? [] : [{ name, with: [...new Set(touched)] }];
  });
}

/**
 * `config` with the `sql` defaults on the named blocks and their dependencies
 * it doesn't list yet, so they render the way doctor renders them once `blocks`
 * lists them.
 */
function withAddedBlocks(
  config: ResolvedConfig,
  names: readonly string[],
): ResolvedConfig {
  const defaults = config.sql.blockDefaults;

  const unlisted = resolveBlocks(names)
    .map((module) => module.name)
    .filter((name) => !(name in config.blocks));

  if (defaults === undefined || unlisted.length === 0) {
    return config;
  }

  return {
    ...config,
    blocks: {
      ...config.blocks,
      ...Object.fromEntries(unlisted.map((name) => [name, defaults])),
    },
  };
}

/**
 * Lists `untracked` in `blocks` of the config file, so `upgrade --check` keeps
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
      "Add them to blocks in better-supabase.config.ts so `upgrade --check` keeps them current:",
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
      "Add them to blocks so `upgrade --check` keeps them current:",
      ...untracked.map((name) => `  ${keyText(name)}: {},`),
    ];
  }

  await applyPlan(
    {
      root: dirname(file),
      regenerate: "better-supabase add",
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
