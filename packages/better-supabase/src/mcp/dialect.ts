import { toDraft07 } from "../generators/json-schema-target.ts";

type Json = Readonly<Record<string, unknown>>;

/**
 * The JSON Schema dialect of tool schemas, which depends on the protocol
 * revision.
 */
export type ToolSchemaTarget = "draft-2020-12" | "draft-07";

/**
 * Revisions before 2025-11-25 have no default dialect, and clients written for
 * them validate tool schemas as draft-07.
 */
export function schemaTargetFor(version: string): ToolSchemaTarget {
  return version < "2025-11-25" ? "draft-07" : "draft-2020-12";
}

/**
 * Returns the listed tool with its schemas in a target's dialect, built once
 * per target. `convert` asks the input's Standard Schema library for the
 * target; without it, or when it can't, the 2020-12 schema is lowered.
 */
export function toolDialects<
  T extends { readonly inputSchema: Json; readonly outputSchema?: Json },
>(
  info: T,
  convert?: (target: ToolSchemaTarget) => Json | undefined,
): (target: ToolSchemaTarget) => T {
  const built = new Map<ToolSchemaTarget, T>();

  return (target) => {
    const cached = built.get(target);

    if (cached) {
      return cached;
    }

    const input = convert?.(target);
    const lower = target === "draft-07";

    const result: T =
      input === undefined && !lower
        ? info
        : {
            ...info,
            inputSchema: input ?? toDraft07(info.inputSchema),
            ...(info.outputSchema && lower
              ? { outputSchema: toDraft07(info.outputSchema) }
              : {}),
          };

    built.set(target, result);

    return result;
  };
}
