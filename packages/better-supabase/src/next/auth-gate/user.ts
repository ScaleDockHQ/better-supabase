"use client";

import type { ReactNode } from "react";

import { createContext, createElement, use, useContext } from "react";

import type { GateUser } from "../user.ts";

const UserContext = createContext<Promise<GateUser | null> | null>(null);

export interface UserProviderProps {
  /** The promise `AuthGate` creates from `bsb.user()`. */
  readonly promise: Promise<GateUser | null>;
  readonly children?: ReactNode;
}

/** Holds the user promise `AuthGate` passes across the server boundary. */
export function UserProvider(props: UserProviderProps): ReactNode {
  return createElement(
    UserContext.Provider,
    { value: props.promise },
    props.children,
  );
}

/**
 * The signed-in user: `use()` on the promise `AuthGate` created, so call it
 * under a `<Suspense>` boundary. It carries no token and no session.
 */
export function useUser(): GateUser | null {
  const promise = useContext(UserContext);

  if (promise === null) {
    throw new Error("better-supabase: useUser() needs an <AuthGate> above it.");
  }

  return use(promise);
}
