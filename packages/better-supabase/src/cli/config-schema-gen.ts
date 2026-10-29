import * as v from "valibot";

import type { DataHooksFramework } from "../config/index.ts";

import { HOOK_FRAMEWORKS } from "./names.ts";

interface SourceInput {
  dbUrl?: string | undefined;
  projectRef?: string | undefined;
  accessToken?: string | undefined;
  snapshot?: string | undefined;
  lite?: boolean | undefined;
}

type HooksInput =
  | DataHooksFramework
  | false
  | {
      framework?: DataHooksFramework | undefined;
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
export const hooksSchema: v.GenericSchema<HooksInput> = v.union([
  v.picklist(HOOK_FRAMEWORKS),
  v.literal(false),
  v.strictObject({
    framework: v.optional(v.picklist(HOOK_FRAMEWORKS)),
    select: v.optional(
      v.strictObject({ module: v.string(), export: v.string() }),
    ),
  }),
]);
