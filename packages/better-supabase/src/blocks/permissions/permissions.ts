import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { BlockTenant } from "../../core/tenant-source.ts";
import type { BlockOptions } from "../shared.ts";
import type {
  PermissionFlags,
  PermissionSet,
} from "./permissions-controller.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { AsyncResult } from "../../core/result.ts";
import {
  blockCall,
  recordOf,
  recordsOf,
  stringsOf,
  textOf,
} from "../shared.ts";
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

/** A per-tenant grant (`true`) or deny (`false`) of one key to a role. */
export interface PermissionOverride {
  readonly permission: string;
  readonly granted: boolean;
}

/** A catalog role and its keys in one tenant, as `roles()` lists it. */
export interface CatalogRole {
  readonly id: string;
  readonly key: string;
  /** How many members of the tenant hold the role. */
  readonly members: number;
  /** The keys the catalog grants the role everywhere. */
  readonly defaultPermissions: readonly string[];
  /** The keys the role holds in this tenant, after its overrides. */
  readonly permissions: readonly string[];
  readonly overrides: readonly PermissionOverride[];
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
    input?: { keys?: readonly K[] | undefined } & AccessCallOptions,
  ): AsyncResult<PermissionSet>;
  /** Whether the caller holds `key`. */
  can(input: { key: K } & AccessCallOptions): AsyncResult<boolean>;
  /**
   * One `can<Name>` boolean per entry of `flags`, in one call: `{ edit:
   * "customers.write" }` resolves to `{ canEdit: true }`.
   */
  flags<const M extends Readonly<Record<string, K>>>(
    input: { flags: M } & AccessCallOptions,
  ): AsyncResult<PermissionFlags<M>>;
  /**
   * The catalog's tenant roles with their keys in the tenant. Catalog model
   * only; needs `members.read`.
   */
  roles(options?: AccessCallOptions): AsyncResult<readonly CatalogRole[]>;
  /**
   * Grants (`true`) or denies (`false`) `permission` to `role` (its key or id)
   * in the tenant; `null` restores the role's default. Catalog model only;
   * needs `roles.manage`, a role the caller could assign and a key the caller
   * holds. Resolves to the role as it stands after the change.
   */
  setOverride(
    input: {
      role: string;
      permission: K;
      granted: boolean | null;
    } & AccessCallOptions,
  ): AsyncResult<CatalogRole>;
}

const keysOf = (value: unknown): readonly string[] =>
  Array.isArray(value)
    ? value.filter((key): key is string => typeof key === "string")
    : [];

function catalogRoleOf(value: unknown): CatalogRole {
  const row = recordOf(value, "list_roles");

  return {
    id: textOf(row["id"]),
    key: textOf(row["key"]),
    members: Number(row["members"] ?? 0),
    defaultPermissions: stringsOf(row["default_permissions"]),
    permissions: stringsOf(row["permissions"]),
    overrides: recordsOf(row["overrides"], "list_roles").map((entry) => ({
      permission: textOf(entry["permission"]),
      granted: entry["granted"] === true,
    })),
  };
}

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
    requireTenant(perCall?.tenant ?? options.tenant).andThen((tenant) =>
      keys?.length === 0
        ? AsyncResult.ok<PermissionSet>({ tenant, keys: [] })
        : call(
            "my_permissions",
            { tenant, keys: keys === undefined ? null : [...new Set(keys)] },
            (value): PermissionSet => ({ tenant, keys: keysOf(value) }),
          ),
    );

  const client: Permissions<K> = {
    permissions: ({ keys, ...perCall } = {}) => load(keys, perCall),
    can: ({ key, ...perCall }) =>
      load([key], perCall).map((set) => can(set, key)),
    flags: ({ flags, ...perCall }) =>
      load(Object.values(flags), perCall).map((set) =>
        permissionFlags(set, flags),
      ),
    roles: (perCall) =>
      requireTenant(perCall?.tenant ?? options.tenant).andThen((tenant) =>
        call("list_roles", { tenant }, (value) =>
          recordsOf(value, "list_roles").map(catalogRoleOf),
        ),
      ),
    setOverride: ({ role, permission, granted, ...perCall }) =>
      requireTenant(perCall.tenant ?? options.tenant).andThen((tenant) =>
        call(
          "set_permission_override",
          { tenant, role, permission, granted },
          catalogRoleOf,
        ),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "permissions",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
