// Client bundles import this through the apps' catalog modules, so it imports nothing.

export type BuildScope = "full" | "minimal";

/** Entries a `minimal` build prerenders per dynamic route. */
const MINIMAL_ENTRIES = 3;

export function isBuildScope(value: string | undefined): value is BuildScope {
  return value === "full" || value === "minimal";
}

/**
 * The `generateStaticParams` result for this build. A `minimal` build keeps the
 * first few entries, and the rest render on their first request.
 */
export function scopeStaticParams<T>(params: readonly T[]): T[] {
  const scope = process.env["BSB_BUILD_SCOPE"];

  return scope === "minimal" ? params.slice(0, MINIMAL_ENTRIES) : [...params];
}
