import { existsSync } from "node:fs";
import { resolve } from "node:path";

import type { FilePlan } from "./core/files.ts";
import type { CommandResult } from "./core/io.ts";
import type { Project } from "./project/detect.ts";
import type { Prompter } from "./prompts.ts";

import { INTEGRATION_INFO } from "../config/index.ts";
import { parseNames } from "./core/errors.ts";
import { display } from "./core/io.ts";
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

/**
 * `--force`, or the person's answer when files exist; `undefined` when they
 * cancel.
 */
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

/**
 * Template files as a plan: each is written once, and an existing file is the
 * app's.
 */
export function templatePlan(
  root: string,
  files: readonly TemplateFile[],
  regenerate: string,
  base: string = root,
): FilePlan {
  return {
    root,
    base,
    regenerate,
    files: files.map((file) => ({
      path: file.path,
      contents: file.contents,
      policy: "create",
    })),
  };
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
      label: INTEGRATION_INFO[name].title,
      hint: INTEGRATION_INFO[name].description,
    })),
    initial,
  );
}

export function parseIntegrations(
  values: readonly string[],
): readonly Integration[] | string {
  return parseNames(values, isIntegration, "integration", INTEGRATIONS);
}
