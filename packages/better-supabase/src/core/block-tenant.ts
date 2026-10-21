import { dbError } from "./errors.ts";
import { AsyncResult } from "./result.ts";

/**
 * Where a block reads the active tenant: an organization id, or a function that
 * returns the current one, such as `() => db.$context.tenant` on the server or
 * the session's tenant claim in the browser.
 */
export type BlockTenant = string | (() => string | null | undefined);

/** The `tenant` option of the blocks whose methods work in one tenant. */
export interface BlockTenantOptions {
  /**
   * The organization the calls act in. `createBlocks` and `createBlockClient`
   * pass the request's tenant; a call without one fails with
   * `TENANT_REQUIRED`.
   */
  readonly tenant?: BlockTenant;
}

/** The tenant `source` names now, or `undefined`. */
export function currentTenant(
  source: BlockTenant | undefined,
): string | undefined {
  const value = typeof source === "function" ? source() : source;

  return value === null || value === undefined || value === ""
    ? undefined
    : value;
}

/**
 * Reads the tenant for one call: `invalid_request` with the hint
 * `TENANT_REQUIRED` when there is none.
 */
export function requireTenant(
  source: BlockTenant | undefined,
): AsyncResult<string> {
  const tenant = currentTenant(source);

  return tenant === undefined
    ? AsyncResult.err(
        dbError(
          "invalid_request",
          "No tenant is active: pass `tenant` to the block, or call it from a request that has one",
          { hint: "TENANT_REQUIRED" },
        ),
      )
    : AsyncResult.ok(tenant);
}
