import { existsSync } from "node:fs";
import { posix, resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliArgs } from "../command.ts";
import type { CommandResult } from "../io.ts";
import type { Prompter } from "../prompts.ts";

import { defineCliCommand, list } from "../command.ts";
import { findConfig } from "../config.ts";
import { display, writeIfChanged } from "../io.ts";
import { detectProject, installCommand, type Project } from "../project.ts";
import {
  baseFiles,
  INTEGRATIONS,
  isIntegration,
  libEntry,
  needsLib,
  resolveIntegrations,
  suggestedIntegrations,
  type Integration,
  type TemplateContext,
  type TemplateFile,
  TEMPLATES,
} from "../templates.ts";
import { VERSION } from "../version.ts";

const WRITE_ARGS = {
  force: { type: "boolean", description: "Overwrite files that exist" },
  "dry-run": { type: "boolean", description: "Show what would be written" },
} as const;

const INIT_ARGS = {
  casing: {
    type: "string",
    description:
      "Row keys in camelCase (camel, the default) or the database's snake_case (snake)",
    valueHint: "camel|snake",
  },
  with: {
    type: "string",
    description:
      "Integrations to add next to the detected ones: next, hono, orpc, edge, mcp, client, react",
    valueHint: "integration,...",
  },
  force: { type: "boolean", description: "Overwrite files that exist" },
  "dry-run": { type: "boolean", description: "Show what would be written" },
} as const;

const ADD_ARGS = {
  integration: {
    type: "positional",
    required: false,
    description: "next, hono, orpc, edge, mcp, client or react",
  },
  force: { type: "boolean", description: "Overwrite files that exist" },
  "dry-run": { type: "boolean", description: "Show what would be written" },
} as const;

type WriteArgs = CliArgs<typeof WRITE_ARGS>;
export type InitArgs = CliArgs<typeof INIT_ARGS>;
export type AddArgs = CliArgs<typeof ADD_ARGS>;

const CANCELLED: CommandResult = { code: 1, error: "Cancelled." };

/** `--force`, or the person's answer when files exist; `undefined` when they cancel. */
async function overwrite(
  root: string,
  files: readonly TemplateFile[],
  args: WriteArgs,
  prompts: Prompter | undefined,
): Promise<boolean | undefined> {
  if (args.force === true) return true;
  const existing = [
    ...new Set(
      files
        .map((file) => file.path)
        .filter((path) => existsSync(resolve(root, path))),
    ),
  ];
  if (!prompts || existing.length === 0) return false;
  return prompts.confirm(
    `${existing.map((path) => display(root, path)).join(", ")} ${existing.length === 1 ? "exists" : "exist"}. Overwrite?`,
  );
}

async function writeFiles(
  root: string,
  files: readonly TemplateFile[],
  args: WriteArgs,
  force: boolean,
): Promise<string[]> {
  const dryRun = args["dry-run"] === true;
  const lines: string[] = [];
  const seen = new Set<string>();
  for (const file of files) {
    if (seen.has(file.path)) continue;
    seen.add(file.path);
    const path = resolve(root, file.path);
    const shown = display(root, file.path);
    if (existsSync(path) && !force) {
      lines.push(`Kept    ${shown} (exists)`);
      continue;
    }
    if (dryRun) {
      lines.push(`Would write ${shown}`);
      continue;
    }
    lines.push(
      `${(await writeIfChanged(path, file.contents)) ? "Wrote  " : "Same   "} ${shown}`,
    );
  }
  return lines;
}

function context(project: Project, generated: string): TemplateContext {
  return {
    srcDir: project.srcDir,
    generated,
    tsExtensions: project.tsExtensions,
    frameworks: project.frameworks,
    version: VERSION,
  };
}

function integrationFiles(
  names: readonly Integration[],
  templateContext: TemplateContext,
): TemplateFile[] {
  return names.flatMap((name) => TEMPLATES[name].files(templateContext));
}

function packagesFor(
  project: Project,
  names: readonly Integration[],
): string[] {
  const wanted = [
    "better-supabase",
    "@supabase/supabase-js",
    ...names.flatMap((name) => TEMPLATES[name].packages),
  ];
  return [...new Set(wanted)].filter((name) => !(name in project.dependencies));
}

/** pg as a dev dependency, when the project lacks it. */
function devPackages(project: Project): string[][] {
  return "pg" in project.dependencies ? [] : [["pg"]];
}

function chooseIntegrations(
  prompts: Prompter,
  initial: readonly Integration[],
): Promise<Integration[] | undefined> {
  return prompts.multiselect(
    "Integrations",
    INTEGRATIONS.map((name) => ({
      value: name,
      label: name,
      hint: TEMPLATES[name].description,
    })),
    initial,
  );
}

function parseIntegrations(values: readonly string[]): Integration[] | string {
  const unknown = values.filter((value) => !isIntegration(value));
  if (unknown.length > 0)
    return `Unknown integration ${unknown.join(", ")}. Available: ${INTEGRATIONS.join(", ")}`;
  return values.filter(isIntegration);
}

export async function runInit(
  config: ResolvedConfig,
  args: InitArgs,
  prompts?: Prompter,
): Promise<CommandResult> {
  const casing =
    args.casing ??
    (prompts
      ? await prompts.select(
          "Row keys",
          [
            { value: "camel", label: "camelCase", hint: "customerId" },
            {
              value: "snake",
              label: "snake_case",
              hint: "customer_id, as in the database",
            },
          ],
          "camel",
        )
      : "camel");
  if (casing === undefined) return CANCELLED;
  if (casing !== "camel" && casing !== "snake") {
    return { code: 2, error: '--casing must be "camel" or "snake"' };
  }
  const project = await detectProject(config.root);
  const requested = parseIntegrations(list(args.with));
  if (typeof requested === "string") return { code: 2, error: requested };
  const detected = resolveIntegrations([
    ...suggestedIntegrations(project.frameworks),
    ...requested,
  ]);
  const chosen =
    args.with === undefined && prompts
      ? await chooseIntegrations(prompts, detected)
      : detected;
  if (chosen === undefined) return CANCELLED;
  const integrations = resolveIntegrations(chosen);
  const hasConfig = findConfig(config.root) !== undefined;
  const generated = hasConfig
    ? config.output
    : posix.normalize(posix.join(project.srcDir, "lib/supabase/generated.ts"));
  const templateContext = context(project, generated);

  const files = [
    ...baseFiles(templateContext, casing, needsLib(integrations)),
    ...integrationFiles(integrations, templateContext),
  ];
  const force = await overwrite(config.root, files, args, prompts);
  if (force === undefined) return CANCELLED;
  const lines = [
    project.frameworks.length > 0
      ? `Found ${project.frameworks.join(", ")}.`
      : "No framework found.",
    "",
    ...(await writeFiles(config.root, files, args, force)),
  ];
  const packages = packagesFor(project, integrations);
  const steps = [
    ...(packages.length > 0
      ? [installCommand(project.packageManager, packages)]
      : []),
    ...devPackages(project).map((names) =>
      installCommand(project.packageManager, names, true),
    ),
    ...(project.hasSupabase ? [] : ["supabase init"]),
    "supabase start",
    "better-supabase env",
    "better-supabase gen",
  ];
  lines.push(
    "",
    "Next:",
    ...steps.map((step, index) => `  ${index + 1}. ${step}`),
  );
  for (const name of integrations) {
    for (const hint of TEMPLATES[name].next ?? []) lines.push(`  - ${hint}`);
  }
  lines.push("", "Agent skills: better-supabase skills install");
  return { code: 0, output: lines.join("\n") };
}

export async function runAdd(
  config: ResolvedConfig,
  args: AddArgs,
  prompts?: Prompter,
): Promise<CommandResult> {
  const named =
    args._.length === 0 && prompts
      ? await chooseIntegrations(prompts, [])
      : args._;
  if (named === undefined) return CANCELLED;
  if (named.length === 0)
    return {
      code: 2,
      error: `Name at least one integration: ${INTEGRATIONS.join(", ")}`,
    };
  const requested = parseIntegrations(named);
  if (typeof requested === "string") return { code: 2, error: requested };
  const project = await detectProject(config.root);
  const integrations = resolveIntegrations(requested);
  const templateContext = context(project, config.output);
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
  return { code: 0, output: lines.join("\n") };
}

export const initCommand: AnyCommand = defineCliCommand({
  meta: {
    name: "init",
    description:
      "Writes better-supabase.config.ts, src/lib/supabase/index.ts and glue for the frameworks in package.json",
  },
  args: INIT_ARGS,
  lists: ["with"],
  run: (args, { config, io }) => runInit(config, args, io.prompts),
});

export const addCommand: AnyCommand = defineCliCommand({
  meta: {
    name: "add",
    description: "Adds glue for an integration to an existing project",
  },
  args: ADD_ARGS,
  run: (args, { config, io }) => runAdd(config, args, io.prompts),
});
