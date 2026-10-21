import type { CreateDesign, Preset, PresetInput } from "../preset/index.ts";
import type { DesignIssue } from "./design-issues.ts";

import {
  designConfig,
  DesignParseError,
  DesignTooLongError,
  designOf,
  encodeDesign,
  encodePreset,
  parseDesign,
  presetOf,
  resolvePreset,
} from "../preset/index.ts";
import { designIssues } from "./design-issues.ts";
import { previewFiles } from "./preview-provider.ts";
import { schemaData } from "./schema-meta.ts";
import { parseSchema, tenantColumnOf } from "./schema.ts";

/** What `checkDesign` returns. */
export type DesignCheck =
  | {
      readonly ok: true;
      /** The design, with its empty parts dropped. */
      readonly design: CreateDesign;
      /** Whether its code fits in a `/create` URL (`MAX_DESIGN_CODE_LENGTH`). */
      readonly fitsUrl: boolean;
      /**
       * Its `encodeDesign` code. `null` only when `fitsUrl` is false; send a
       * design file then.
       */
      readonly code: string | null;
    }
  | {
      readonly ok: false;
      /**
       * Each problem, with a stable `code` and a JSON Pointer `path` into the
       * design; `table` is `design` or `preset` for one outside a table.
       */
      readonly issues: readonly DesignIssue[];
    };

const messageOf = (error: unknown): string =>
  error instanceof Error ? error.message : String(error);

/** The issue for a design that failed to parse, with its code and path. */
function parseIssue(error: unknown): DesignIssue {
  const { code, path } =
    error instanceof DesignParseError
      ? error
      : { code: "invalid_design" as const, path: "" };

  return { code, path, table: tableAt(path), message: messageOf(error) };
}

/** The app table or block module a design path is in, or `design`. */
function tableAt(path: string): string {
  const [, key, name] = path.split("/");

  return (key === "appTables" || key === "extraColumns") && name !== undefined
    ? name.replaceAll("~1", "/").replaceAll("~0", "~")
    : "design";
}

async function designFrom(input: unknown): Promise<CreateDesign> {
  if (typeof input !== "string") {
    return parseDesign(input);
  }

  const design = await designOf(input);

  if (design === undefined) {
    throw new DesignParseError(
      "invalid_code",
      "",
      `design: "${input.slice(0, 40)}" is neither a design code nor a /create URL with &design=`,
    );
  }

  return design;
}

/**
 * Checks a design against a preset with every rule the canvas and `sql sync`
 * apply, so a server, an MCP tool and the canvas share one answer. `input` is a
 * design object, a design code or a `/create` URL with `&design=`. It never
 * throws for a bad design or preset: each problem is an issue.
 */
export async function checkDesign(
  input: unknown,
  preset: PresetInput,
): Promise<DesignCheck> {
  let design: CreateDesign;

  try {
    design = await designFrom(input);
  } catch (error) {
    return { ok: false, issues: [parseIssue(error)] };
  }

  let resolvedPreset: Preset;

  try {
    resolvedPreset = presetOf(preset);
  } catch (error) {
    return {
      ok: false,
      issues: [
        {
          code: "invalid_preset",
          path: "",
          table: "preset",
          message: messageOf(error),
        },
      ],
    };
  }

  const resolved = resolvePreset(resolvedPreset);

  if (resolved.conflicts.length > 0) {
    return {
      ok: false,
      issues: resolved.conflicts.map((conflict) => ({
        code: "preset_conflict",
        path: "",
        table: "preset",
        message: `${conflict.block ?? conflict.field ?? "preset"}: ${conflict.reason}`,
      })),
    };
  }

  try {
    designConfig(resolved, design);
  } catch (error) {
    return { ok: false, issues: [parseIssue(error)] };
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
    return {
      ok: true,
      design,
      fitsUrl: true,
      code: await encodeDesign(design),
    };
  } catch (error) {
    if (error instanceof DesignTooLongError) {
      return { ok: true, design, fitsUrl: false, code: null };
    }

    return { ok: false, issues: [parseIssue(error)] };
  }
}
