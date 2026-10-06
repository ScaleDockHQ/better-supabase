import type { CountMode } from "../ir/types.ts";

const COUNT_MODES = new Set<unknown>(["exact", "planned", "estimated"]);

function isCountMode(value: unknown): value is CountMode {
  return COUNT_MODES.has(value);
}

/** `maxAffected` from a call, or a message when it isn't a non-negative integer. */
export function maxAffectedOf(
  args: Readonly<Record<string, unknown>>,
): { maxAffected?: number } | { invalid: string } {
  const value = args["maxAffected"];
  if (value === undefined) return {};
  return typeof value === "number" && Number.isInteger(value) && value >= 0
    ? { maxAffected: value }
    : {
        invalid: `"maxAffected" must be a non-negative integer, got ${String(value)}`,
      };
}

/** The `count` mode a mutation asks for, when it names a valid one. */
export function countOf(args: Readonly<Record<string, unknown>> | undefined): {
  count?: CountMode;
} {
  const count = args?.["count"];
  return isCountMode(count) ? { count } : {};
}
