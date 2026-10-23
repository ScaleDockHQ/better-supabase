"use client";

import type { BlockEnv } from "better-supabase/blocks";
import type {
  PermissionsActions,
  PermissionSource,
  PermissionsSnapshot,
} from "better-supabase/blocks/permissions";
import type { ReactNode } from "react";

import { envBlockOptions } from "better-supabase/blocks";
import {
  batchPermissions,
  can,
  createPermissions,
  createPermissionsController,
} from "better-supabase/blocks/permissions";
import {
  useBlockEnv,
  useBlockTenant,
  useController,
} from "better-supabase/react";

export type { PermissionSet } from "better-supabase/blocks/permissions";

const sources = new WeakMap<BlockEnv["supabase"], PermissionSource>();

/** One batched access client per supabase-js client, shared by its hooks. */
function sourceOf(env: BlockEnv): PermissionSource {
  let source = sources.get(env.supabase);

  if (source === undefined) {
    source = batchPermissions(
      createPermissions(envBlockOptions(env, "access")),
    );
    sources.set(env.supabase, source);
  }

  return source;
}

export interface UsePermissionsOptions {
  /** The organization to check in. Default the client's tenant. */
  readonly tenant?: string;
}

export interface PermissionsState<K extends string = string>
  extends PermissionsSnapshot, PermissionsActions {
  /** Whether the caller holds `key`; false while loading. */
  readonly can: (key: K) => boolean;
}

/**
 * Which of `keys` the caller holds in the client's tenant, through the access
 * contract. The hooks rendered in the same tick share one `my_permissions`
 * call. UX only: RLS checks every key again.
 *
 * ```tsx
 * const { can } = usePermissions([permissions.invoices.write]);
 * ```
 */
export function usePermissions<const K extends string>(
  keys: readonly K[],
  options: UsePermissionsOptions = {},
): PermissionsState<K> {
  const env = useBlockEnv();
  const current = useBlockTenant(env);
  const tenant = options.tenant ?? current;
  const key = [...new Set(keys)].toSorted().join("\n");

  const { view } = useController(
    () =>
      createPermissionsController<K>({
        // SAFETY: the shared source checks any key; `K` only narrows the result.
        client: sourceOf(env),
        auth: env.auth,
        // SAFETY: `key` joins the keys of `keys`, all `K`.
        keys: (key === "" ? [] : key.split("\n")) as K[],
        tenant,
      }),
    [env, tenant, key],
  );

  return { ...view, can: (wanted) => can(view.permissions, wanted) };
}

/**
 * Whether the caller holds `key` in the client's tenant: `undefined` while it
 * loads, then true or false.
 *
 * ```tsx
 * const canEdit = usePermission(permissions.invoices.write);
 * ```
 */
export function usePermission<const K extends string>(
  key: K,
  options: UsePermissionsOptions = {},
): boolean | undefined {
  const { permissions, can: holds } = usePermissions([key], options);

  return permissions === undefined ? undefined : holds(key);
}

export interface CanProps<K extends string = string> {
  /** The permission key, such as `permissions.invoices.write`. */
  readonly permission: K;
  /** The organization to check in. Default the client's tenant. */
  readonly tenant?: string;
  /** Shown while loading and when the caller lacks the key. Default nothing. */
  readonly fallback?: ReactNode;
  readonly children?: ReactNode;
}

/**
 * Renders `children` when the caller holds `permission`, else `fallback`.
 *
 * ```tsx
 * <Can permission={permissions.invoices.write}>
 *   <Button>Edit</Button>
 * </Can>;
 * ```
 */
export function Can<const K extends string>(props: CanProps<K>): ReactNode {
  const allowed = usePermission(
    props.permission,
    props.tenant === undefined ? {} : { tenant: props.tenant },
  );

  return allowed === true ? props.children : (props.fallback ?? null);
}
