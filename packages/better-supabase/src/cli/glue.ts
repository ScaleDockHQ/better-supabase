import { existsSync } from "node:fs";
import { resolve } from "node:path";

import type { CommandResult } from "./io.ts";
import type { Project } from "./project.ts";
import type { Prompter } from "./prompts.ts";

import { parseNames } from "./errors.ts";
import { display, writeIfChanged } from "./io.ts";
import {
  INTEGRATIONS,
  isIntegration,
  type Integration,
  type TemplateContext,
  type TemplateFile,
  TEMPLATES,
} from "./templates.ts";
import { VERSION } from "./version.ts";

export interface WriteFlags {
  readonly force?: boolean | undefined;
  readonly "dry-run"?: boolean | undefined;
}

export const CANCELLED: CommandResult = { code: 1, error: "Cancelled." };

/** `--force`, or the person's answer when files exist; `undefined` when they cancel. */
export async function overwrite(
  root: string,
  files: readonly TemplateFile[],
  args: WriteFlags,
  prompts: Prompter | undefined,
  base: string = root,
): Promise<boolean | undefined> {
  if (args.force === true) {
    return true;
  }

  const existing = [
    ...new Set(
      files
        .map((file) => file.path)
        .filter((path) => existsSync(resolve(root, path))),
    ),
  ];

  if (!prompts || existing.length === 0) {
    return false;
  }

  return prompts.confirm(
    `${existing.map((path) => display(base, resolve(root, path))).join(", ")} ${existing.length === 1 ? "exists" : "exist"}. Overwrite?`,
  );
}

export async function writeFiles(
  root: string,
  files: readonly TemplateFile[],
  args: WriteFlags,
  force: boolean,
  base: string = root,
): Promise<string[]> {
  const dryRun = args["dry-run"] === true;
  const lines: string[] = [];
  const seen = new Set<string>();

  for (const file of files) {
    if (seen.has(file.path)) {
      continue;
    }

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

export function templateContextFor(
  project: Project,
  generated: string,
): TemplateContext {
  return {
    srcDir: project.srcDir,
    generated,
    tsExtensions: project.tsExtensions,
    frameworks: project.frameworks,
    version: VERSION,
  };
}

export function integrationFiles(
  names: readonly Integration[],
  templateContext: TemplateContext,
): TemplateFile[] {
  return names.flatMap((name) => TEMPLATES[name].files(templateContext));
}

export function packagesFor(
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

export function chooseIntegrations(
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

export function parseIntegrations(
  values: readonly string[],
): readonly Integration[] | string {
  return parseNames(values, isIntegration, "integration", INTEGRATIONS);
}
