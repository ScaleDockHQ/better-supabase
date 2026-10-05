import { existsSync } from "node:fs";
import { join, posix, resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliArgs } from "../command.ts";
import type { CommandResult } from "../io.ts";
import type { Prompter } from "../prompts.ts";

import { defineCliCommand, list } from "../command.ts";
import { findConfig, loadConfig } from "../config.ts";
import { display, writeIfChanged } from "../io.ts";
import {
  detectProject,
  installCommand,
  type InstallTarget,
  type Project,
} from "../project.ts";
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
import { detectWorkspace, suggestedPackage } from "../workspace.ts";

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
  package: {
    type: "string",
    description: "Workspace package to write to, relative to --cwd",
    valueHint: "dir",
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
  base: string = root,
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
    `${existing.map((path) => display(base, resolve(root, path))).join(", ")} ${existing.length === 1 ? "exists" : "exist"}. Overwrite?`,
  );
}

async function writeFiles(
  root: string,
  files: readonly TemplateFile[],
  args: WriteArgs,
  force: boolean,
  base: string = root,
): Promise<string[]> {
  const dryRun = args["dry-run"] === true;
  const lines: string[] = [];
  const seen = new Set<string>();
  for (const file of files) {
    if (seen.has(file.path)) continue;
    seen.add(file.path);
    const path = resolve(root, file.path);
    const shown = display(base, path);
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

/** Where `init` writes: `--cwd`, `--package`, or the workspace package the person picks. */
async function initTarget(
  cwd: string,
  args: InitArgs,
  prompts: Prompter | undefined,
): Promise<{ readonly dir: string } | CommandResult> {
  if (args.package !== undefined) {
    const dir = posix.normalize(args.package.replaceAll("\\", "/"));
    if (!existsSync(join(cwd, dir, "package.json"))) {
      return {
        code: 2,
        error: `--package ${args.package} has no package.json. Pass the directory of a workspace package, relative to --cwd.`,
      };
    }
    return { dir: dir.replace(/\/$/, "") || "." };
  }
  const workspace = await detectWorkspace(cwd);
  if (!workspace || workspace.packages.length === 0) return { dir: "." };
  const suggested = suggestedPackage(workspace) ?? ".";
  if (!prompts) {
    return {
      code: 2,
      error: `${workspace.file} makes this a workspace root. Pass --package with the package that owns the runtime (${workspace.packages.map((entry) => entry.dir).join(", ")}), or --package . to write here.`,
    };
  }
  const dir = await prompts.select(
    "Package that owns the runtime",
    [
      ...workspace.packages.map((entry) => ({
        value: entry.dir,
        label: entry.dir,
        ...(entry.project.name ? { hint: entry.project.name } : {}),
      })),
      { value: ".", label: ".", hint: "the workspace root" },
    ],
    suggested,
  );
  return dir === undefined ? CANCELLED : { dir };
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
  const target = await initTarget(config.root, args, prompts);
  if ("code" in target) return target;
  const root = resolve(config.root, target.dir);
  const inPackage = target.dir !== ".";
  const workspaceProject = await detectProject(config.root);
  const project: Project = inPackage
    ? {
        ...(await detectProject(root)),
        packageManager: workspaceProject.packageManager,
      }
    : workspaceProject;
  const installTarget: InstallTarget | undefined = inPackage
    ? { dir: target.dir, name: project.name }
    : undefined;
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
  const hasConfig = findConfig(root) !== undefined;
  let generated = posix.normalize(
    posix.join(project.srcDir, "lib/supabase/generated.ts"),
  );
  if (hasConfig)
    generated = inPackage ? (await loadConfig(root)).output : config.output;
  const templateContext = context(project, generated);

  const files = [
    ...baseFiles(templateContext, casing, needsLib(integrations)),
    ...integrationFiles(integrations, templateContext),
  ];
  const force = await overwrite(root, files, args, prompts, config.root);
  if (force === undefined) return CANCELLED;
  const where = inPackage ? ` in ${target.dir}` : "";
  const lines = [
    project.frameworks.length > 0
      ? `Found ${project.frameworks.join(", ")}${where}.`
      : `No framework found${where}.`,
    "",
    ...(await writeFiles(root, files, args, force, config.root)),
  ];
  const packages = packagesFor(project, integrations);
  const cwdFlag = inPackage ? ` --cwd ${target.dir}` : "";
  const steps = [
    ...(packages.length > 0
      ? [installCommand(project.packageManager, packages, false, installTarget)]
      : []),
    ...devPackages(project).map((names) =>
      installCommand(project.packageManager, names, true, installTarget),
    ),
    ...(project.hasSupabase || workspaceProject.hasSupabase
      ? []
      : ["supabase init"]),
    "supabase start",
    `better-supabase env${cwdFlag}`,
    `better-supabase gen${cwdFlag}`,
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
