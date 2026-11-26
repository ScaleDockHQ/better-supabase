import type { ReactNode } from "react";

import { createContext, createElement, useContext } from "react";

const TenantContext = createContext<{ readonly value: unknown } | undefined>(
  undefined,
);

/**
 * Holds the tenant record a layout read with `bsb.tenant()` or
 * `bsb.activeTenant()`, so client components read it with `useTenant()` instead
 * of taking `orgSlug` and `organizationId` as props. Pass plain data: the value
 * crosses the server and client boundary.
 */
export function TenantProvider<T>({
  value,
  children,
}: {
  readonly value: T;
  readonly children: ReactNode;
}): ReactNode {
  return createElement(TenantContext, { value: { value } }, children);
}

/** The nearest `TenantProvider`'s record. Throws outside one. */
export function useTenant<T = { readonly id: string }>(): T {
  const held = useContext(TenantContext);

  if (held === undefined) {
    throw new Error("useTenant() needs a <TenantProvider> above it.");
  }

  // SAFETY: the provider stores what its `value` prop typed as `T`.
  return held.value as T;
}
