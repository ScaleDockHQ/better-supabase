import * as v from "valibot";

import type { HooksFramework } from "../config/index.ts";

import { HOOK_FRAMEWORKS } from "./names.ts";

interface SourceInput {
  dbUrl?: string | undefined;
  projectRef?: string | undefined;
  accessToken?: string | undefined;
  snapshot?: string | undefined;
  lite?: boolean | undefined;
}

type HooksInput =
  | HooksFramework
  | false
  | {
      framework?: HooksFramework | undefined;
      select?: { module: string; export: string } | undefined;
    };

/** `gen.source`: where `gen` reads the schema from. */
export const sourceSchema: v.GenericSchema<SourceInput> = v.strictObject({
  dbUrl: v.optional(v.string()),
  projectRef: v.optional(v.string()),
  accessToken: v.optional(v.string()),
  snapshot: v.optional(v.string()),
  lite: v.optional(v.boolean()),
});

/** `gen.hooks`: a framework, `false`, or a framework with a select wrapper. */
/**
 * A built-in name, which the JSON Schema lists for completion, or the name of a
 * registered binding, which `resolveConfig` checks against the registry.
 */
const frameworkName = v.union([
  v.picklist(HOOK_FRAMEWORKS),
  v.pipe(
    v.string(),
    v.regex(
      /^[a-z][a-z0-9-]*$/,
      "a framework name is lowercase letters, digits and dashes",
    ),
  ),
]);

export const hooksSchema: v.GenericSchema<HooksInput> = v.union([
  frameworkName,
  v.literal(false),
  v.strictObject({
    framework: v.optional(frameworkName),
    select: v.optional(
      v.strictObject({ module: v.string(), export: v.string() }),
    ),
  }),
]);
