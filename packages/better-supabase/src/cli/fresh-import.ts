import { registerHooks } from "node:module";
import { pathToFileURL } from "node:url";

const RUN = "better-supabase-run";

/**
 * Tags every file a fresh import reaches outside `node_modules` with the
 * entry's run, so Node loads them again too. Packages keep one instance, so
 * brand checks across modules still hold.
 */
function tagLocalImports(): void {
  registerHooks({
    resolve(specifier, context, next) {
      const resolved = next(specifier, context);
      const parent = context.parentURL;
      if (
        parent === undefined ||
        !parent.startsWith("file:") ||
        !resolved.url.startsWith("file:") ||
        resolved.url.includes("/node_modules/")
      )
        return resolved;
      const run = new URL(parent).searchParams.get(RUN);
      if (run === null) return resolved;
      const url = new URL(resolved.url);
      url.searchParams.set(RUN, run);
      return { ...resolved, url: url.href };
    },
  });
}

let runs = 0;

/**
 * Imports a project module and the project files it imports as they are on
 * disk now, so watch loops see edits to a read-set module's dependencies
 * (such as the `generated.ts` the previous run wrote). Each call keeps its
 * copy of those modules in memory for the life of the process.
 */
export async function importFresh(
  path: string,
): Promise<Record<string, unknown>> {
  if (runs === 0) tagLocalImports();
  runs += 1;
  const url = pathToFileURL(path);
  url.searchParams.set(RUN, String(runs));
  // SAFETY: an ES module namespace is an object of its exports.
  return (await import(url.href)) as Record<string, unknown>;
}
