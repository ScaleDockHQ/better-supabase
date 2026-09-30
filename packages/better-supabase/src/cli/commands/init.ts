import { existsSync } from "node:fs";
import { posix, resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { ParsedArgs } from "../args.ts";
import type { CommandResult } from "../io.ts";

import { flagList, flagBool, flagString } from "../args.ts";
import { findConfig } from "../config.ts";
import { display, writeIfChanged } from "../io.ts";
import { detectProject, installCommand, type Project } from "../project.ts";
import {
  baseFiles,
  INTEGRATIONS,
  isIntegration,
  libDir,
  needsLib,
  resolveIntegrations,
  suggestedIntegrations,
  type Integration,
  type TemplateContext,
  type TemplateFile,
  TEMPLATES,
} from "../templates.ts";
import { VERSION } from "../version.ts";

export const INIT_HELP: string = `Usage: better-supabase init [--casing camel|snake] [--with <integration...>] [--force] [--dry-run]

Writes better-supabase.config.ts and src/lib/supabase.ts, plus glue for the
frameworks it finds in package.json. Existing files are kept unless --force.

Integrations: ${INTEGRATIONS.join(", ")}`;

export const ADD_HELP: string = `Usage: better-supabase add <integration...> [--force] [--dry-run]

Integrations
${INTEGRATIONS.map((name) => `  ${name.padEnd(8)} ${TEMPLATES[name].description}`).join("\n")}`;

async function writeFiles(
  root: string,
  files: readonly TemplateFile[],
  args: ParsedArgs,
): Promise<string[]> {
  const force = flagBool(args.flags, "force");
  const dryRun = flagBool(args.flags, "dry-run");
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

function parseIntegrations(values: readonly string[]): Integration[] | string {
  const unknown = values.filter((value) => !isIntegration(value));
  if (unknown.length > 0)
    return `Unknown integration ${unknown.join(", ")}. Available: ${INTEGRATIONS.join(", ")}`;
  return values.filter(isIntegration);
}

export async function runInit(
  config: ResolvedConfig,
  args: ParsedArgs,
): Promise<CommandResult> {
  const casing = flagString(args.flags, "casing") ?? "camel";
  if (casing !== "camel" && casing !== "snake") {
    return { code: 2, error: '--casing must be "camel" or "snake"' };
  }
  const project = await detectProject(config.root);
  const requested = parseIntegrations(flagList(args.flags, "with"));
  if (typeof requested === "string") return { code: 2, error: requested };
  const integrations = resolveIntegrations([
    ...suggestedIntegrations(project.frameworks),
    ...requested,
  ]);
  const hasConfig = findConfig(config.root) !== undefined;
  const generated = hasConfig
    ? config.output
    : posix.normalize(posix.join(project.srcDir, "lib/supabase/generated.ts"));
  const templateContext = context(project, generated);

  const lines = [
    project.frameworks.length > 0
      ? `Found ${project.frameworks.join(", ")}.`
      : "No framework found.",
    "",
    ...(await writeFiles(
      config.root,
      [
        ...baseFiles(templateContext, casing, needsLib(integrations)),
        ...integrationFiles(integrations, templateContext),
      ],
      args,
    )),
  ];
  const packages = packagesFor(project, integrations);
  const steps = [
    ...(packages.length > 0
      ? [installCommand(project.packageManager, packages)]
      : []),
    ...("pg" in project.dependencies
      ? []
      : [installCommand(project.packageManager, ["pg"], true)]),
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
  args: ParsedArgs,
): Promise<CommandResult> {
  if (args.rest.length === 0) return { code: 2, error: ADD_HELP };
  const requested = parseIntegrations(args.rest);
  if (typeof requested === "string")
    return { code: 2, error: `${requested}\n\n${ADD_HELP}` };
  const project = await detectProject(config.root);
  const integrations = resolveIntegrations(requested);
  const templateContext = context(project, config.output);
  const lines = await writeFiles(
    config.root,
    integrationFiles(integrations, templateContext),
    args,
  );
  const lib = posix.join(libDir(templateContext), "supabase.ts");
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
