import type { ReactNode } from "react";

import { forbidden } from "next/dist/client/components/forbidden.js";
import { redirect } from "next/dist/client/components/redirect.js";
import { unauthorized } from "next/dist/client/components/unauthorized.js";
import { Fragment, Suspense, createElement } from "react";

import type { GateUser } from "../user.ts";

import { UserProvider } from "./user.js";

// Kept external by tsdown so it stays a `'use client'` module: this Server
// Component renders the provider and passes the user promise across.
export { UserProvider, useUser } from "./user.js";

export type { GateUser } from "../user.ts";

export type { UserProviderProps } from "./user.ts";

export interface AuthGateProps {
  /**
   * Loads the user in a `"use cache: private"` function that returns
   * `bsb.user()`. The gate never reads the session itself, so the layout stays
   * out of the dynamic render.
   */
  readonly user: () => Promise<GateUser | null>;
  readonly children: ReactNode;
  /** Shown while the user loads. Defaults to nothing. */
  readonly fallback?: ReactNode;
  /** Where a signed-out visitor goes. The proxy already redirects most. */
  readonly redirect?: string;
  /** Answer a signed-out visitor with `forbidden()` or `unauthorized()`. */
  readonly refuse?: "forbidden" | "unauthorized";
  /**
   * Runs before the first `<Suspense>`, so a status it sets (`redirect()`,
   * `forbidden()`, `unauthorized()`) is the response's. Awaiting a request API
   * here makes the layout dynamic, so leave it out when the proxy checks.
   */
  readonly check?: () => unknown;
}

interface GateProps {
  readonly user: () => Promise<GateUser | null>;
  readonly children?: ReactNode;
  readonly redirect: string | undefined;
  readonly refuse: "forbidden" | "unauthorized" | undefined;
}

async function Gate(props: GateProps): Promise<ReactNode> {
  const promise = props.user();
  const user = await promise;

  if (user === null) {
    if (props.refuse === "forbidden") {
      forbidden();
    }

    if (props.refuse === "unauthorized") {
      unauthorized();
    }

    if (props.redirect !== undefined) {
      redirect(props.redirect);
    }

    return null;
  }

  // The key makes a user change remount the subtree, never reuse the last
  // user's DOM.
  return createElement(
    Fragment,
    { key: user.id },
    createElement(UserProvider, { promise }, props.children),
  );
}

/**
 * A Server Component for the app layout: it wraps the children in a
 * `<Suspense>` around one `bsb.user()` promise and hands it to `useUser()` in
 * Client Components, keyed on the user id.
 *
 * ```tsx
 * <AuthGate user={getUser} fallback={<Shell />} redirect="/sign-in">
 *   {children}
 * </AuthGate>;
 * ```
 */
export async function AuthGate(props: AuthGateProps): Promise<ReactNode> {
  await props.check?.();

  return createElement(
    Suspense,
    { fallback: props.fallback ?? null },
    createElement(
      Gate,
      { user: props.user, redirect: props.redirect, refuse: props.refuse },
      props.children,
    ),
  );
}
