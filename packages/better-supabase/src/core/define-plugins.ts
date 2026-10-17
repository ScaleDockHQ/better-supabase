import type { Executor } from "./executor.ts";
import type { AnyPlugin } from "./plugin.ts";

export function isExecutor(value: unknown): value is Executor {
  // SAFETY: value is a non-null object here, and each property read is type-checked.
  return (
    typeof value === "object" &&
    value !== null &&
    typeof (value as Executor).execute === "function" &&
    typeof (value as Executor).name === "string"
  );
}

/** No plugins, one shared array so the caches keyed on a plugin list hit. */
export const NO_PLUGINS: readonly AnyPlugin[] = Object.freeze([]);

/** The kept lists per installed list and `keep` names, so each is one stable array. */
const keptLists = new WeakMap<
  readonly AnyPlugin[],
  Map<string, readonly AnyPlugin[]>
>();

/** The installed plugins named in `keep`; a name that isn't installed throws, so a typo can't drop tracing silently. */
export function keptPlugins(
  plugins: readonly AnyPlugin[],
  keep: readonly string[],
): readonly AnyPlugin[] {
  if (keep.length === 0) {
    return NO_PLUGINS;
  }

  let byKeep = keptLists.get(plugins);

  if (!byKeep) {
    byKeep = new Map();
    keptLists.set(plugins, byKeep);
  }

  const key = keep.join("\u0000");
  const cached = byKeep.get(key);

  if (cached) {
    return cached;
  }

  for (const name of keep) {
    if (!plugins.some((plugin) => plugin.name === name)) {
      throw new TypeError(
        `better-supabase: $withoutPlugins({ keep }) names "${name}", which is not installed. Installed: ${plugins.map((plugin) => plugin.name).join(", ") || "none"}`,
      );
    }
  }

  const kept = plugins.filter((plugin) => keep.includes(plugin.name));
  byKeep.set(key, kept);

  return kept;
}
