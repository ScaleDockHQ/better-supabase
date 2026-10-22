import { existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliArgs, CliOptions } from "../core/command.ts";
import type { CommandResult, NextStep } from "../core/io.ts";
import type { Prompter } from "../prompts.ts";
import type { TemplateContext } from "../templates.ts";
import type { SqlDeps } from "./sql.ts";

import {
  DEFAULT_CONVENTIONS,
  glueCommand,
  PRESET_CATALOG,
  PRESET_FRAMEWORKS,
  resolvePreset,
} from "../../preset/index.ts";
import { defineCliCommand, list } from "../core/command.ts";
import { CliError } from "../core/errors.ts";
import {
  applyPlan,
  changeLines,
  PLAN_ARGS,
  planResult,
} from "../core/files.ts";
import { readIfExists } from "../core/io.ts";
import { commandMeta } from "../core/manifest.ts";
import {
  CANCELLED,
  chooseIntegrations,
  integrationFiles,
  overwrite,
  packagesFor,
  parseIntegrations,
  templateContextFor,
  templatePlan,
} from "../glue.ts";
import { detectProject, installCommand } from "../project/detect.ts";
import { addModules } from "../sql/add.ts";
import { addBlocksToWiring } from "../sql/config-edit.ts";
import {
  importFrom,
  INTEGRATIONS,
  libEntry,
  needsLib,
  resolveIntegrations,
  TEMPLATES,
} from "../templates.ts";
import { blockNames } from "./blocks.ts";

const ADD_ARGS = {
  block: {
    type: "positional",
    required: false,
    variadic: true,
    description:
      "Blocks to install with what they require (`better-supabase blocks list`). Without blocks or --integration, sets up the integrations in the config that have no files yet",
  },
  integration: {
    type: "string",
    description:
      "Adds glue for integrations instead: next, hono, orpc, edge, expo, mcp, client or react",
    valueHint: "integration,...",
  },
  force: { type: "boolean", description: "Overwrite files that exist" },
  "allow-hook-overlap": {
    type: "boolean",
    description:
      "With blocks: write modules whose claim the authorization provider's hook already writes",
  },
  "tests-dir": {
    type: "string",
    description:
      "With blocks: where the pgtap module goes. Defaults to database.sql.testsDir",
    valueHint: "dir",
  },
} as const;

export type AddArgs = CliArgs<
  typeof ADD_ARGS & Pick<typeof PLAN_ARGS, "dry-run" | "check">
>;

/**
 * Adds blocks: lists them in `blocks`, writes their modules and what they
 * require (`sql add`), wires the ones with a client into `lib/blocks.ts`, and
 * names the registry glue for the project's frameworks.
 */
async function addBlocks(
  config: ResolvedConfig,
  args: AddArgs,
  names: readonly string[],
  deps: SqlDeps,
): Promise<CommandResult> {
  const added = await addModules(
    config,
    { ...args, _: ["add", ...names] },
    names,
    deps,
  );

  if (added.code !== 0) {
    return added;
  }

  const lines = [added.output ?? ""];
  const project = await detectProject(config.root);
  const context = templateContextFor(project, config.output);

  const resolved = resolvePreset({
    ...DEFAULT_CONVENTIONS,
    blocks: [...config.blockNames, ...names],
  });

  const wanted = new Set(
    resolvePreset({ ...DEFAULT_CONVENTIONS, blocks: names }).manifests.map(
      (manifest) => manifest.name,
    ),
  );

  const clients = resolved.manifests.flatMap((manifest) =>
    manifest.client === null || !wanted.has(manifest.name)
      ? []
      : [
          {
            key: manifest.name.replaceAll(/-([a-z0-9])/g, (_, letter: string) =>
              letter.toUpperCase(),
            ),
            export: manifest.client.export,
            subpath: manifest.client.subpath,
          },
        ],
  );

  if (clients.length > 0) {
    const wiring = blocksWiringPath(context);
    const path = resolve(config.root, wiring);
    const current = await readIfExists(path);

    const edit =
      current === undefined ? undefined : addBlocksToWiring(current, clients);

    if (edit?.ok === true && edit.text !== current) {
      await applyPlan(
        {
          root: config.root,
          regenerate: "better-supabase add",
          files: [{ path, contents: edit.text, policy: "edit" }],
        },
        { "dry-run": args["dry-run"] },
      );

      lines.push(
        "",
        `${args["dry-run"] === true ? "Would wire" : "Wired"} ${clients.map((client) => client.key).join(", ")} in ${wiring}.`,
      );
    } else if (edit?.ok !== true) {
      lines.push(
        "",
        `Wire the clients in ${wiring}${edit === undefined ? " (it doesn't exist yet)" : ` (${edit.reason})`}:`,
        ...clients.map(
          (client) =>
            `  import { ${client.export} } from "${client.subpath}";  // ${client.key}: ${client.export}`,
        ),
      );
    }
  }

  const frameworks = PRESET_FRAMEWORKS.filter(
    (framework) =>
      config.integrations.some((name) => name === framework) ||
      project.frameworks.some((name) => name === framework),
  );

  const installed = new Set(resolved.blocks.map((block) => block.name));

  const glue = PRESET_CATALOG.glue.filter(
    (item) =>
      item.preset === undefined &&
      item.blocks.some((block) => names.includes(block)) &&
      item.blocks.every((block) => installed.has(block)) &&
      item.frameworks.some((framework) =>
        frameworks.some((each) => each === framework),
      ),
  );

  const glueLine = glue.length > 0 ? glueCommand(glue) : undefined;

  if (glueLine !== undefined) {
    lines.push("", `Glue for ${frameworks.join(", ")}: ${glueLine}`);
  }

  return {
    code: 0,
    output: lines.join("\n"),
    data: {
      blocks: names,
      modules: added.data,
      clients: clients.map((client) => client.key),
      ...(glueLine === undefined ? {} : { glue: glueLine }),
    },
  };
}

/** `lib/blocks.ts` next to `lib/supabase/`. */
export function blocksWiringPath(context: TemplateContext): string {
  return join(dirname(dirname(libEntry(context))), "blocks.ts");
}

/**
 * How `lib/blocks.ts` imports the `blocks.generated.ts` that `gen` writes next
 * to `generated.ts`.
 */
export function blockConfigImport(context: TemplateContext): string {
  return importFrom(
    context,
    blocksWiringPath(context),
    join(dirname(context.generated), "blocks.generated.ts"),
  );
}

const SYSTEM_DEPS: SqlDeps = { now: () => new Date() };

export async function runAdd(
  config: ResolvedConfig,
  args: AddArgs,
  prompts?: Prompter,
  deps: SqlDeps = SYSTEM_DEPS,
): Promise<CommandResult> {
  if (args._.length > 0 && args.integration === undefined) {
    return addBlocks(config, args, args._, deps);
  }

  if (args.integration !== undefined) {
    return addIntegrations(
      config,
      { ...args, _: list(args.integration) },
      prompts,
    );
  }

  return addIntegrations(config, args, prompts);
}

async function addIntegrations(
  config: ResolvedConfig,
  args: CliOptions<typeof ADD_ARGS> & { readonly _: readonly string[] },
  prompts?: Prompter,
): Promise<CommandResult> {
  const project = await detectProject(config.root);

  const templateContext = templateContextFor(
    project,
    config.output,
    config.blockNames.length > 0,
  );

  const fromConfig = args._.length === 0 && config.integrations.length > 0;

  const missing = config.integrations.filter((name) =>
    integrationFiles([name], templateContext).some(
      (file) => !existsSync(resolve(config.root, file.path)),
    ),
  );

  if (fromConfig && missing.length === 0) {
    return {
      code: 0,
      output: `Every integration in the config is set up: ${config.integrations.join(", ")}.`,
      data: { integrations: [], files: [], packages: [], unlisted: [] },
    };
  }

  const named = fromConfig
    ? missing
    : args._.length === 0 && prompts
      ? await chooseIntegrations(prompts, [])
      : args._;

  if (named === undefined) {
    return CANCELLED;
  }

  if (named.length === 0) {
    throw new CliError(
      "usage",
      `Name at least one integration (${INTEGRATIONS.join(", ")}), or list them in integrations in the config.`,
    );
  }

  const requested = parseIntegrations(named);

  if (typeof requested === "string") {
    throw new CliError("usage", requested);
  }

  const integrations = resolveIntegrations(requested);
  const files = integrationFiles(integrations, templateContext);
  const force = await overwrite(config.root, files, args, prompts);

  if (force === undefined) {
    return CANCELLED;
  }

  const plan = templatePlan(config.root, files, "better-supabase add");
  const applied = await applyPlan(plan, { ...args, force });

  if (applied.mode === "check" && applied.drift) {
    return planResult(plan, applied);
  }

  const lines = changeLines(applied);
  const lib = libEntry(templateContext);

  const libMissing =
    !existsSync(resolve(config.root, lib)) &&
    integrations.some((name) => needsLib([name]));

  const next: NextStep[] = [];

  if (libMissing) {
    next.push({ command: "better-supabase init", when: `${lib} is missing` });
    lines.push(
      "",
      `Warning: ${lib} is missing. Run \`better-supabase init\` first.`,
    );
  }

  const packages = packagesFor(project, integrations).filter(
    (name) => name !== "better-supabase" && name !== "@supabase/supabase-js",
  );

  const install =
    packages.length > 0
      ? installCommand(project.packageManager, packages)
      : undefined;

  if (install !== undefined) {
    lines.push("", `Install: ${install}`);
    next.push({ command: install, when: "to install the packages they need" });
  }

  for (const name of integrations) {
    for (const hint of TEMPLATES[name].next ?? []) {
      lines.push(`- ${hint}`);
    }
  }

  const unlisted = integrations.filter(
    (name) => !config.integrations.includes(name),
  );

  if (unlisted.length > 0) {
    lines.push(
      "",
      "Add them to your config so `better-supabase add` sets them up in a fresh checkout:",
      `  adapters: [${[...config.integrations, ...unlisted].map((name) => `'${name}'`).join(", ")}]`,
    );
  }

  return {
    code: 0,
    output: lines.join("\n"),
    data: { integrations, files: applied.changes, packages, unlisted },
    next,
  };
}

export const addCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("add"),
  args: {
    ...ADD_ARGS,
    "dry-run": PLAN_ARGS["dry-run"],
    check: PLAN_ARGS.check,
  },
  lists: ["integration"],
  completions: { block: blockNames },
  run: (args, { config, configFile, io }) =>
    runAdd(config, args, io.prompts, {
      ...SYSTEM_DEPS,
      ...(configFile === undefined ? {} : { configFile }),
    }),
});
