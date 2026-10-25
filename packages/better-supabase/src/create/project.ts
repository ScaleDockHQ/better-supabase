import type { CreateDesign, Preset, PresetInput } from "../preset/index.ts";
import type { Issue } from "./issue.ts";
import type { PreviewOptions } from "./preview-provider.ts";
import type { PresetMigrationFile } from "./types.ts";

import { presetOf } from "../preset/index.ts";
import { checkDesign } from "./check.ts";
import { designIssues } from "./design-issues.ts";
import { previewFiles } from "./preview-provider.ts";
import { schemaData } from "./schema-meta.ts";
import { parseSchema, tenantColumnOf } from "./schema.ts";

/**
 * A project: the preset and design that say which blocks and app tables it has,
 * and the files they render to over the tables it already owns (ADR 0100). The
 * CLI, Create and the cloud read and check the same shape.
 */
export interface Project {
  readonly preset: Preset;
  /** The design, with its empty parts dropped. */
  readonly design: CreateDesign;
  /** The files `upgrade` would write. */
  readonly files: readonly PresetMigrationFile[];
  /** The tables the files were rendered over, when the project had any. */
  readonly ownTables?: PreviewOptions["ownTables"];
}

export type ProjectLoad =
  | { readonly ok: true; readonly project: Project }
  | { readonly ok: false; readonly issues: readonly Issue[] };

export interface LoadProjectOptions extends PreviewOptions {
  /** The preset, when `input` is a design without one. */
  readonly preset?: PresetInput;
}

/**
 * Reads a project from a design object, a design code or a `/create` URL with
 * `&design=`, with the preset inside the design or in `options.preset`. It
 * never throws for a bad project: each problem is an `Issue`.
 */
export async function loadProject(
  input: unknown,
  options: LoadProjectOptions = {},
): Promise<ProjectLoad> {
  const fallback = options.preset ?? "saas";

  const checked = await checkDesign(input, fallback);

  if (!checked.ok) {
    return { ok: false, issues: checked.issues };
  }

  const preset = presetOf(checked.design.preset ?? fallback);

  try {
    return {
      ok: true,
      project: {
        preset,
        design: checked.design,
        files: previewFiles(preset, checked.design, options),
        ...(options.ownTables === undefined
          ? {}
          : { ownTables: options.ownTables }),
      },
    };
  } catch (error) {
    return {
      ok: false,
      issues: [
        {
          code: "invalid_design",
          severity: "error",
          source: "design",
          path: "",
          table: "design",
          message: error instanceof Error ? error.message : String(error),
        },
      ],
    };
  }
}

export interface CheckProjectOptions {
  /**
   * Applies the files in Postgres and returns what it rejects, such as
   * `sqlIssues` from `better-supabase/create/lite`. Left out, no SQL runs.
   */
  readonly sql?: (
    files: readonly PresetMigrationFile[],
  ) => Promise<readonly Issue[]>;
}

/**
 * Every problem in a project, as one list of `Issue`: the design rules (names,
 * references, keys, defaults), then the SQL Postgres rejects when `options.sql`
 * runs it. An empty list means the project can be written.
 */
export async function checkProject(
  project: Project,
  options: CheckProjectOptions = {},
): Promise<readonly Issue[]> {
  const data = schemaData(
    parseSchema(previewFiles(project.preset), {
      tenantColumn: tenantColumnOf(project.preset),
    }),
    project.preset.tenantName,
  );

  const issues = [...designIssues(project.design, data, project.preset)];

  if (options.sql !== undefined) {
    issues.push(...(await options.sql(project.files)));
  }

  return issues;
}
