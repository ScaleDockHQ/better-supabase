import type { ResolveAuthOptions } from "../auth/resolve.ts";
import type { ActionResult } from "../server/kit.ts";
import type { SignInCredentials, SignInOptions, SignedIn } from "./types.ts";

import { clientIp } from "../auth/resolve.ts";
import { sessionCookieName, writeSession } from "../auth/session.ts";
import { needsMfa, passwordGrant, safeRedirectPath } from "../auth/sign-in.ts";

interface CookieJar {
  getAll(): readonly { readonly name: string; readonly value: string }[];
  set(name: string, value: string, options: object): unknown;
}

export interface SignInDeps {
  readonly env: {
    readonly url: string;
    readonly publishableKey: string;
    readonly secretKey?: string | undefined;
  };
  readonly auth: Omit<ResolveAuthOptions, "env"> | undefined;
  readonly request: Request;
  readonly jar: CookieJar;
  /** Stores the verified session, so the next render doesn't verify again. */
  readonly seed: (accessToken: string) => Promise<void>;
}

/**
 * Signs in on the server, writes the session cookies through the request's
 * cookie jar and returns the same-origin path to go to next.
 */
export async function signInWithPassword(
  credentials: SignInCredentials,
  options: SignInOptions,
  deps: SignInDeps,
): Promise<ActionResult<SignedIn>> {
  const { env, auth } = deps;
  const secretKey = env.secretKey;

  const ip =
    secretKey && auth?.clientIp !== false
      ? (auth?.clientIp ?? clientIp)(deps.request)
      : undefined;

  const granted = await passwordGrant(
    { email: credentials.email, password: credentials.password },
    {
      url: env.url,
      publishableKey: env.publishableKey,
      ...(secretKey && ip ? { forwardedFor: { ip, secretKey } } : {}),
      ...(auth?.fetch ? { fetch: auth.fetch } : {}),
      ...(auth?.refreshTimeoutMs === undefined
        ? {}
        : { timeoutMs: auth.refreshTimeoutMs }),
    },
  );

  if (!granted.ok) {
    return granted;
  }

  const writes = writeSession(
    deps.jar.getAll(),
    auth?.cookie?.name ?? sessionCookieName(env.url),
    granted.data,
    auth?.cookie?.options,
    auth?.cookie?.encode === undefined ? {} : { encode: auth.cookie.encode },
  );

  for (const write of writes) {
    deps.jar.set(write.name, write.value, write.options);
  }

  await deps.seed(granted.data.access_token);

  return {
    ok: true,
    data: {
      redirectTo: safeRedirectPath(credentials.next, options.fallback ?? "/"),
      mfa: needsMfa(granted.data),
    },
    error: null,
  };
}
