import type { ReactNode } from "react";

import { createContext, createElement, useContext } from "react";

import type { BootstrapPermissions } from "../core/bootstrap-permissions.ts";

import { expandBootstrapPermissions } from "../core/bootstrap-permissions.ts";

const PermissionsContext = createContext<BootstrapPermissions | undefined>(
  undefined,
);

/**
 * Whether `key` is held. A platform key matches every tenant. Without a tenant,
 * any tenant that holds the key matches.
 */
export function can(
  permissions: BootstrapPermissions | undefined,
  key: string,
  tenant?: string,
): boolean {
  if (permissions === undefined) {
    return false;
  }

  if (permissions.platform.includes(key)) {
    return true;
  }

  if (tenant === undefined) {
    return Object.values(permissions.tenants).some((keys) =>
      keys.includes(key),
    );
  }

  return permissions.tenants[tenant]?.includes(key) ?? false;
}

/**
 * Holds the bootstrap permissions for client checks. Pass either wire form
 * (`full` or `compact`); a value this version does not understand grants
 * nothing.
 */
export function PermissionsProvider({
  value,
  children,
}: {
  readonly value: unknown;
  readonly children: ReactNode;
}): ReactNode {
  return createElement(
    PermissionsContext,
    { value: expandBootstrapPermissions(value) },
    children,
  );
}

/** `can(key)` against the nearest `PermissionsProvider`. */
export function useCan(key: string, tenant?: string): boolean {
  return can(useContext(PermissionsContext), key, tenant);
}
