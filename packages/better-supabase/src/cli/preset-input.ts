import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import {
  type CreateDesign,
  designOf,
  isPresetName,
  type Preset,
  presetOf,
  readDesignFile,
} from "../preset/index.ts";
import { CliError } from "./core/errors.ts";

/** The preset and design `--preset` names. */
export interface PresetInputValue {
  readonly preset: Preset;
  readonly design: CreateDesign | undefined;
}

/** Whether `--preset` names a design file rather than a preset or URL. */
const isDesignFilePath = (input: string): boolean => input.endsWith(".json");

/**
 * Reads `--preset`: a named preset, a code, a `/create` URL, or the path of a
 * design file Create downloaded (relative to `root`). Throws a usage error
 * naming the problem.
 */
export async function readPresetInput(
  input: string,
  root: string,
): Promise<PresetInputValue> {
  try {
    if (isDesignFilePath(input)) {
      const path = resolve(root, input);

      if (!existsSync(path)) {
        throw new TypeError(
          `${input} doesn't exist. Download the design file from Create, or pass a preset name, code or URL.`,
        );
      }

      return readDesignFile(await readFile(path, "utf-8"));
    }

    return {
      preset: presetOf(input),
      design: isPresetName(input) ? undefined : await designOf(input),
    };
  } catch (error) {
    throw new CliError(
      "usage",
      error instanceof Error ? error.message : String(error),
    );
  }
}
