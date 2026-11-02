import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliArgs } from "../core/command.ts";
import type { PlannedFile } from "../core/files.ts";
import type { CommandResult, NextStep } from "../core/io.ts";
import type { Paint } from "../style.ts";

import {
  DEFAULT_CONVENTIONS,
  PRESET_CATALOG,
  removeComposite,
  resolvePreset,
} from "../../preset/index.ts";
import { renderBlocks } from "../../sql/index.ts";
import { defineCliCommand } from "../core/command.ts";
import { CliError } from "../core/errors.ts";
import {
  applyPlan,
  changeLines,
  HAND_EDITED,
  PLAN_ARGS,
  planResult,
} from "../core/files.ts";
import { display, readIfExists } from "../core/io.ts";
import { commandMeta } from "../core/manifest.ts";
import { templateContextFor } from "../glue.ts";
import { detectProject } from "../project/detect.ts";
import { sqlPlan } from "../sql-layout.ts";
import { isComposite } from "../sql/add.ts";
import { SQL_ARGS } from "../sql/args.ts";
import { addBlocksToConfig, addBlocksToJson } from "../sql/config-edit.ts";
import { layoutFor } from "../sql/providers.ts";
import {
  removeBlocksFromConfig,
  removeBlocksFromJson,
  removeBlocksFromWiring,
} from "../sql/remove-edit.ts";
import { guardedRemoval } from "../sql/write.ts";
import { plain } from "../style.ts";
import { blockClients, blocksWiringPath } from "./add.ts";
import { blockNames } from "./blocks.ts";

const REMOVE_ARGS = {
  block: {
    type: "positional",
    required: false,
    variadic: true,
    description:
      "Blocks to remove: their config entries, their clients in lib/blocks.ts, and the schema files no other block needs",
  },
  "with-parts": {
    type: "boolean",
    description:
      "With a composite block, remove its parts too, except the ones another block still needs. Without it the parts stay as their own blocks",
  },
} as const;

export type RemoveArgs = CliArgs<
  typeof REMOVE_ARGS &
    Pick<typeof PLAN_ARGS, "dry-run" | "check"> &
    Pick<typeof SQL_ARGS, "force">
>;

/** What `runRemove` reads from outside. */
export interface RemoveDeps {
  readonly configFile?: string;
  readonly paint?: Paint;
}

/** The blocks `names` and what they require, as `resolvePreset` resolves them. */
const resolved = (names: readonly string[]) =>
  resolvePreset({ ...DEFAULT_CONVENTIONS, blocks: names });

/**
 * Takes blocks out of the config and `lib/blocks.ts`, and deletes the schema
 * and test files only they wrote. The tables stay in the database until the
 * migration that `db diff` writes from the smaller schema runs.
 */
export async function runRemove(
  config: ResolvedConfig,
  args: RemoveArgs,
  deps: RemoveDeps = {},
): Promise<CommandResult> {
  const names = [...new Set(args._)];

  if (names.length === 0) {
    throw new CliError(
      "usage",
      "Name the blocks to remove, e.g. `better-supabase remove comments`.",
    );
  }

  const unknown = names.filter((name) => !config.blockNames.includes(name));

  if (unknown.length > 0) {
    throw new CliError(
      "usage",
      `${unknown.join(", ")} ${unknown.length === 1 ? "isn't" : "aren't"} in blocks. Installed: ${config.blockNames.join(", ") || "none"}.`,
    );
  }

  const composites = names.filter(isComposite);

  if (args["with-parts"] === true && composites.length === 0) {
    throw new CliError(
      "usage",
      "--with-parts applies to a composite block; none of the named blocks is one.",
    );
  }

  const installed = { ...DEFAULT_CONVENTIONS, blocks: config.blockNames };

  const released = composites.flatMap((name) => {
    const removal = removeComposite(
      installed,
      name,
      { withParts: args["with-parts"] === true },
      PRESET_CATALOG,
    );

    return removal.blocks.filter((block) => !config.blockNames.includes(block));
  });

  const remaining = [
    ...config.blockNames.filter((name) => !names.includes(name)),
    ...released,
  ];

  const after = resolved(remaining);

  const needed = after.blocks.filter((block) => names.includes(block.name));

  if (needed.length > 0) {
    throw new CliError(
      "usage",
      needed
        .map(
          (block) =>
            `${block.name} is required by ${block.requiredBy.join(", ")}; remove those too, or keep it.`,
        )
        .join("\n"),
    );
  }

  const file = deps.configFile;

  if (file === undefined) {
    throw new CliError(
      "usage",
      `No config file: take ${names.join(", ")} out of blocks yourself.`,
    );
  }

  const source = await readFile(file, "utf-8");

  const edit = file.endsWith(".json")
    ? removeBlocksFromJson(source, names)
    : removeBlocksFromConfig(source, names);

  if (!edit.ok) {
    throw new CliError(
      "usage",
      `${display(config.root, file)} wasn't changed: ${edit.reason}. Take ${names.join(", ")} out of blocks yourself.`,
    );
  }

  const listed =
    released.length === 0
      ? edit
      : file.endsWith(".json")
        ? addBlocksToJson(edit.text, released)
        : addBlocksToConfig(edit.text, released);

  if (!listed.ok) {
    throw new CliError(
      "usage",
      `${display(config.root, file)} wasn't changed: ${listed.reason}. List ${released.join(", ")} in blocks yourself.`,
    );
  }

  const files: PlannedFile[] = [
    { path: file, contents: listed.text, policy: "edit" },
  ];

  const lines: string[] = [];
  const kept = new Set(after.manifests.map((manifest) => manifest.name));

  const unwired = blockClients(
    resolved(config.blockNames).manifests.filter(
      (manifest) => !kept.has(manifest.name),
    ),
  );

  if (unwired.length > 0) {
    const project = await detectProject(config.root);
    const wiring = blocksWiringPath(templateContextFor(project, config.output));
    const current = await readIfExists(resolve(config.root, wiring));

    if (current !== undefined) {
      const unwire = removeBlocksFromWiring(current, unwired);

      if (unwire.ok) {
        files.push({ path: wiring, contents: unwire.text, policy: "edit" });
      } else {
        lines.push(
          `Take ${unwired.map((client) => client.key).join(", ")} out of ${wiring} yourself (${unwire.reason}).`,
        );
      }
    }
  }

  const before = renderBlocks(
    config.blockNames,
    await layoutFor(config, {}, config.blockNames),
  );

  const still = new Set(
    renderBlocks(remaining, await layoutFor(config, {}, remaining)).map(
      (entry) => entry.path,
    ),
  );

  const gone = before
    .map((entry) => entry.path)
    .filter(
      (path) => !still.has(path) && existsSync(resolve(config.root, path)),
    );

  const plan = sqlPlan(config, {
    regenerate: "better-supabase remove",
    files,
    remove: gone.map((path) => guardedRemoval(path)),
  });

  const applied = await applyPlan(plan, args, deps.paint ?? plain);

  const edited = applied.changes
    .filter((change) => change.reason === HAND_EDITED)
    .map((change) => change.file);

  const data = {
    blocks: names,
    removed: gone.filter(
      (path) => !edited.includes(display(config.root, path)),
    ),
  };

  if (applied.mode === "check" || edited.length > 0) {
    return planResult(plan, applied, { data });
  }

  const migration = `remove_${names.join("_").replaceAll("-", "_")}`;

  const next: NextStep[] = [
    {
      command: `better-supabase db diff -f ${migration}`,
      when: "to write the migration that drops their tables",
    },
  ];

  return {
    code: 0,
    output: [
      ...changeLines(applied),
      ...lines,
      "",
      applied.mode === "dry-run"
        ? "Dry run: nothing written."
        : `Removed ${names.join(", ")}. Their tables stay until a migration drops them: run \`better-supabase db diff -f ${migration}\`.`,
    ].join("\n"),
    data,
    next,
  };
}

export const removeCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("remove"),
  args: {
    ...REMOVE_ARGS,
    "dry-run": PLAN_ARGS["dry-run"],
    check: PLAN_ARGS.check,
    force: SQL_ARGS.force,
    "with-parts": REMOVE_ARGS["with-parts"],
  },
  completions: { block: blockNames },
  run: (args, { config, configFile, paint }) =>
    runRemove(config, args, {
      paint,
      ...(configFile === undefined ? {} : { configFile }),
    }),
});
