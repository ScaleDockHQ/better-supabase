import type { BlockTenant } from "./tenant-source.ts";

import { dbError } from "./errors.ts";
import { AsyncResult } from "./result.ts";
import { currentTenant } from "./tenant-source.ts";

/** The `tenant` option of the blocks whose methods work in one tenant. */
export interface BlockTenantOptions {
  /**
   * The organization the calls act in. `createBlocks` and `createBlockClient`
   * pass the request's tenant; a call without one fails with
   * `TENANT_REQUIRED`.
   */
  readonly tenant?: BlockTenant;
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
