/**
 * Where a block reads the active tenant: an organization id, or a function that
 * returns the current one, such as `() => db.$context.tenant` on the server or
 * the session's tenant claim in the browser.
 */
export type BlockTenant = string | (() => string | null | undefined);

/** The tenant `source` names now, or `undefined`. */
export function currentTenant(
  source: BlockTenant | undefined,
): string | undefined {
  const value = typeof source === "function" ? source() : source;

  return value === null || value === undefined || value === ""
    ? undefined
    : value;
}
