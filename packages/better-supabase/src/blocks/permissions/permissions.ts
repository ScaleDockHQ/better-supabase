import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { BlockTenant } from "../../core/tenant-source.ts";
import type { BlockOptions } from "../shared.ts";
import type {
  PermissionFlags,
  PermissionSet,
} from "./permissions-controller.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireOrganization } from "../../core/block-tenant.ts";
import { AsyncResult } from "../../core/result.ts";
import { blockCall } from "../shared.ts";
import { can, permissionFlags } from "./permissions-controller.ts";

export interface PermissionsOptions extends BlockOptions {
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: BlockHooks<Permissions>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

/** Which tenant one call checks in, instead of the block's `tenant`. */
export interface AccessCallOptions {
  readonly tenant?: BlockTenant;
}

/**
 * The caller's permissions in the block's tenant, through the access contract:
 * the roles or catalog model, the app's own functions, or the
 * `AuthorizationProvider`. `K` types the keys; annotate the client as
 * `Access<PermissionKey>` with the key union `gen` writes.
 */
export interface Permissions<K extends string = string> {
  /**
   * The keys of `keys` the caller holds, checked one by one with `can()`.
   * Without `keys`, every key the access model lists for the caller, wildcards
   * included; the `custom` model lists none, so pass the keys you check.
   */
  permissions(
    keys?: readonly K[],
    options?: AccessCallOptions,
  ): AsyncResult<PermissionSet>;
  /** Whether the caller holds `key`. */
  can(key: K, options?: AccessCallOptions): AsyncResult<boolean>;
  /**
   * One `can<Name>` boolean per entry of `flags`, in one call: `{ edit:
   * "customers.write" }` resolves to `{ canEdit: true }`.
   */
  flags<const M extends Readonly<Record<string, K>>>(
    flags: M,
    options?: AccessCallOptions,
  ): AsyncResult<PermissionFlags<M>>;
}

const keysOf = (value: unknown): readonly string[] =>
  Array.isArray(value)
    ? value.filter((key): key is string => typeof key === "string")
    : [];

/**
 * The `access` module's `my_permissions` as typed calls. It acts in the block's
 * `tenant`; `createBlocks` and `createBlockClient` pass the request's.
 */
export function createPermissions<K extends string = string>(
  options: PermissionsOptions,
): Permissions<K> {
  const call = blockCall(options.transport, options.schema, options.mappers);

  const load = (
    keys: readonly string[] | undefined,
    perCall: AccessCallOptions | undefined,
  ): AsyncResult<PermissionSet> =>
    requireOrganization(perCall?.tenant ?? options.tenant).andThen((tenant) =>
      keys?.length === 0
        ? AsyncResult.ok<PermissionSet>({ tenant, keys: [] })
        : call(
            "my_permissions",
            { tenant, keys: keys === undefined ? null : [...new Set(keys)] },
            (value): PermissionSet => ({ tenant, keys: keysOf(value) }),
          ),
    );

  const client: Permissions<K> = {
    permissions: (keys, perCall) => load(keys, perCall),
    can: (key, perCall) => load([key], perCall).map((set) => can(set, key)),
    flags: (flags, perCall) =>
      load(Object.values(flags), perCall).map((set) =>
        permissionFlags(set, flags),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "permissions",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
