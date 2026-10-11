import { existsSync } from "node:fs";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliArgs } from "../command.ts";
import type { CommandResult } from "../io.ts";
import type { Prompter } from "../prompts.ts";

import { defineCliCommand } from "../command.ts";
import {
  CANCELLED,
  chooseIntegrations,
  integrationFiles,
  overwrite,
  packagesFor,
  parseIntegrations,
  templateContextFor,
  writeFiles,
} from "../glue.ts";
import { detectProject, installCommand } from "../project.ts";
import {
  INTEGRATIONS,
  libEntry,
  needsLib,
  resolveIntegrations,
  TEMPLATES,
} from "../templates.ts";

const ADD_ARGS = {
  integration: {
    type: "positional",
    required: false,
    description:
      "next, hono, orpc, edge, expo, mcp, client or react. Defaults to the integrations in the config that have no files yet",
  },
  force: { type: "boolean", description: "Overwrite files that exist" },
  "dry-run": { type: "boolean", description: "Show what would be written" },
} as const;

export type AddArgs = CliArgs<typeof ADD_ARGS>;

export async function runAdd(
  config: ResolvedConfig,
  args: AddArgs,
  prompts?: Prompter,
): Promise<CommandResult> {
  const project = await detectProject(config.root);
  const templateContext = templateContextFor(project, config.output);
  const fromConfig = args._.length === 0 && config.integrations.length > 0;
  const missing = config.integrations.filter((name) =>
    integrationFiles([name], templateContext).some(
      (file) => !existsSync(resolve(config.root, file.path)),
    ),
  );
  if (fromConfig && missing.length === 0)
    return {
      code: 0,
      output: `Every integration in the config is set up: ${config.integrations.join(", ")}.`,
    };
  const named = fromConfig
    ? missing
    : args._.length === 0 && prompts
      ? await chooseIntegrations(prompts, [])
      : args._;
  if (named === undefined) return CANCELLED;
  if (named.length === 0)
    return {
      code: 2,
      error: `Name at least one integration (${INTEGRATIONS.join(", ")}), or list them in integrations in the config.`,
    };
  const requested = parseIntegrations(named);
  if (typeof requested === "string") return { code: 2, error: requested };
  const integrations = resolveIntegrations(requested);
  const files = integrationFiles(integrations, templateContext);
  const force = await overwrite(config.root, files, args, prompts);
  if (force === undefined) return CANCELLED;
  const lines = await writeFiles(config.root, files, args, force);
  const lib = libEntry(templateContext);
  if (
    !existsSync(resolve(config.root, lib)) &&
    integrations.some((name) => needsLib([name]))
  ) {
    lines.push(
      "",
      `Warning: ${lib} is missing. Run \`better-supabase init\` first.`,
    );
  }
  const packages = packagesFor(project, integrations).filter(
    (name) => name !== "better-supabase" && name !== "@supabase/supabase-js",
  );
  if (packages.length > 0)
    lines.push(
      "",
      `Install: ${installCommand(project.packageManager, packages)}`,
    );
  for (const name of integrations) {
    for (const hint of TEMPLATES[name].next ?? []) lines.push(`- ${hint}`);
  }
  const unlisted = integrations.filter(
    (name) => !config.integrations.includes(name),
  );
  if (unlisted.length > 0)
    lines.push(
      "",
      "Add them to your config so `better-supabase add` sets them up in a fresh checkout:",
      `  integrations: [${[...config.integrations, ...unlisted].map((name) => `'${name}'`).join(", ")}]`,
    );
  return { code: 0, output: lines.join("\n") };
}

export const addCommand: AnyCommand = defineCliCommand({
  meta: {
    name: "add",
    description: "Adds glue for an integration to an existing project",
  },
  args: ADD_ARGS,
  run: (args, { config, io }) => runAdd(config, args, io.prompts),
});
