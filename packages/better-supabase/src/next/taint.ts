import * as react from "react";

import type { AuthResolution } from "../auth/resolve.ts";

import { ssrSession } from "../auth/session.ts";

type TaintObject = (message: string, object: object) => void;

type TaintValue = (
  message: string,
  lifetime: object,
  ...values: string[]
) => void;

// SAFETY: React's stable types omit the experimental taint functions; each use below checks that the export exists.
const api: typeof react & TaintApi = react;

interface TaintApi {
  readonly experimental_taintUniqueValue?: TaintValue;
  readonly experimental_taintObjectReference?: TaintObject;
}

/**
 * The taint function of React's experimental build, or `undefined`. The `in`
 * check keeps a strict module mock from throwing on a missing export.
 */
function objectTaint(): TaintObject | undefined {
  return "experimental_taintObjectReference" in react
    ? api.experimental_taintObjectReference
    : undefined;
}

function valueTaint(): TaintValue | undefined {
  return "experimental_taintUniqueValue" in react
    ? api.experimental_taintUniqueValue
    : undefined;
}

/**
 * Whether this React build has the taint API (Next.js with
 * `experimental.taint`).
 */
export function taintAvailable(): boolean {
  return objectTaint() !== undefined;
}

/**
 * Makes React refuse to serialize `object` to a Client Component. Without the
 * taint API it does nothing, so the data transfer rule (`bsb.user()`) stays the
 * first layer.
 */
export function taintObject(message: string, object: object): void {
  objectTaint()?.(message, object);
}

/** Makes React refuse to serialize `value` while `lifetime` is alive. */
function taintValue(
  message: string,
  lifetime: object,
  value: string | undefined,
): void {
  if (value !== undefined && value !== "") {
    valueTaint()?.(message, lifetime, value);
  }
}

/**
 * Taints the resolved auth state, its access token and the request's refresh
 * token. The tokens live as long as the state object.
 */
export async function taintResolution(
  resolution: AuthResolution,
  cookieName: string,
): Promise<void> {
  if (!taintAvailable()) {
    return;
  }

  const { auth } = resolution;

  taintObject(
    "better-supabase: the auth state never goes to the client.",
    auth,
  );

  if (auth.kind === "user") {
    taintValue(
      "better-supabase: the access token never goes to the client.",
      auth,
      auth.token,
    );
  }

  const stored = await ssrSession(resolution.requestCookies, cookieName);

  taintValue(
    "better-supabase: the refresh token never goes to the client.",
    auth,
    stored?.refresh_token,
  );
}

/**
 * Wraps `bsb.admin()` so the service-role context it returns can't reach a
 * Client Component.
 */
export function taintedAdmin<A extends unknown[], T extends object>(
  admin: (...args: A) => T,
): (...args: A) => T {
  return (...args) => {
    const context = admin(...args);
    taintObject(
      "better-supabase: the service-role context never goes to the client.",
      context,
    );

    return context;
  };
}
