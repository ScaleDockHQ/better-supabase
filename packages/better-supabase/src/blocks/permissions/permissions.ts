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

/** Why a member does or doesn't hold one key, as `explain()` reports it. */
export type PermissionReason =
  | "granted_by_role"
  | "granted_by_override"
  | "denied_by_override"
  | "role_lacks_key"
  | "not_a_member"
  | "not_in_scope"
  | "member_disabled"
  | "organization_disabled";

export interface PermissionExplanation {
  readonly permission: string;
  readonly userId: string;
  readonly organizationId: string;
  /** What `can()` answers for this member. */
  readonly allowed: boolean;
  readonly reason: PermissionReason;
  /** The roles the member holds in the tenant, as the membership stores them. */
  readonly roles: readonly string[];
  /** The granted keys, wildcards included, that match `permission`. */
  readonly matchedBy: readonly string[];
  /**
   * The tenant override for the member's roles: `true` grants, `false` denies,
   * `null` when none applies (always `null` outside the catalog model).
   */
  readonly override: boolean | null;
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
   * Why `userId` does or doesn't hold `key` in the tenant: the answer `can()`
   * gives, the member's roles, the granted keys that match and a reason.
   * Callers explain themselves; members with `members.read` explain anyone in
   * the tenant. A `forContext({ permissions })` cap shows as `not_in_scope`.
   */
  explain(
    input: { userId: string; key: K } & AccessCallOptions,
  ): AsyncResult<PermissionExplanation>;
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

const REASONS: readonly PermissionReason[] = [
  "granted_by_role",
  "granted_by_override",
  "denied_by_override",
  "role_lacks_key",
  "not_a_member",
  "not_in_scope",
  "member_disabled",
  "organization_disabled",
];

function reasonOf(value: unknown): PermissionReason {
  const found = REASONS.find((reason) => reason === value);

  if (found === undefined) {
    throw new TypeError("explain_permission returned an unknown reason");
  }

  return found;
}

function explanationOf(value: unknown): PermissionExplanation {
  const row = recordOf(value, "explain_permission");

  return {
    permission: textOf(row["permission"]),
    userId: textOf(row["userId"]),
    organizationId: textOf(row["organizationId"]),
    allowed: row["allowed"] === true,
    reason: reasonOf(row["reason"]),
    roles: stringsOf(row["roles"]),
    matchedBy: stringsOf(row["matchedBy"]),
    override: typeof row["override"] === "boolean" ? row["override"] : null,
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
    explain: ({ userId, key, ...perCall }) =>
      requireTenant(perCall.tenant ?? options.tenant).andThen((tenant) =>
        call(
          "explain_permission",
          { tenant, member: userId, permission: key },
          explanationOf,
        ),
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
