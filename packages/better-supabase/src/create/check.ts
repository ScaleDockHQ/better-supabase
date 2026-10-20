import type { DesignIssue } from "./design.ts";

import {
  type CreateDesign,
  designConfig,
  DesignTooLongError,
  designOf,
  encodeDesign,
  encodePreset,
  parseDesign,
  type Preset,
  type PresetInput,
  presetOf,
  resolvePreset,
} from "../preset/index.ts";
import { designIssues } from "./design.ts";
import { previewFiles } from "./preview-provider.ts";
import { schemaData } from "./schema-meta.ts";
import { parseSchema, tenantColumnOf } from "./schema.ts";

/** What `checkDesign` returns. */
export type DesignCheck =
  | {
      readonly ok: true;
      /** The design, with its empty parts dropped. */
      readonly design: CreateDesign;
      /** Its `encodeDesign` code, or `null` when it is too long for a URL. */
      readonly code: string | null;
    }
  | {
      readonly ok: false;
      /** Each problem; `table` is `design` or `preset` for one outside a table. */
      readonly issues: readonly DesignIssue[];
    };

const messageOf = (error: unknown): string =>
  error instanceof Error ? error.message : String(error);

async function designFrom(input: unknown): Promise<CreateDesign> {
  if (typeof input !== "string") {
    return parseDesign(input);
  }

  const design = await designOf(input);

  if (design === undefined) {
    throw new TypeError(
      `design: "${input.slice(0, 40)}" is neither a design code nor a /create URL with &design=`,
    );
  }

  return design;
}

/**
 * Checks a design against a preset with every rule the canvas and
 * `sql sync` apply, so a server, an MCP tool and the canvas share one
 * answer. `input` is a design object, a design code or a `/create` URL with
 * `&design=`. It never throws for a bad design or preset: each problem is
 * an issue.
 */
export async function checkDesign(
  input: unknown,
  preset: PresetInput,
): Promise<DesignCheck> {
  let design: CreateDesign;

  try {
    design = await designFrom(input);
  } catch (error) {
    return {
      ok: false,
      issues: [{ table: "design", message: messageOf(error) }],
    };
  }

  let resolvedPreset: Preset;

  try {
    resolvedPreset = presetOf(preset);
  } catch (error) {
    return {
      ok: false,
      issues: [{ table: "preset", message: messageOf(error) }],
    };
  }

  const resolved = resolvePreset(resolvedPreset);

  if (resolved.conflicts.length > 0) {
    return {
      ok: false,
      issues: resolved.conflicts.map((conflict) => ({
        table: "preset",
        message: `${conflict.block ?? conflict.field ?? "preset"}: ${conflict.reason}`,
      })),
    };
  }

  try {
    designConfig(resolved, design);
  } catch (error) {
    return {
      ok: false,
      issues: [{ table: "design", message: messageOf(error) }],
    };
  }

  const code = encodePreset(resolvedPreset);

  const data = schemaData(
    parseSchema(previewFiles(code), {
      tenantColumn: tenantColumnOf(resolvedPreset),
    }),
    resolvedPreset.tenantName,
  );

  const issues = designIssues(design, data, resolvedPreset);

  if (issues.length > 0) {
    return { ok: false, issues };
  }

  try {
    return { ok: true, design, code: await encodeDesign(design) };
  } catch (error) {
    if (error instanceof DesignTooLongError) {
      return { ok: true, design, code: null };
    }

    return {
      ok: false,
      issues: [{ table: "design", message: messageOf(error) }],
    };
  }
}
