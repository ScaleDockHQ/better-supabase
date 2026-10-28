import type { AuthResolution, AuthState } from "../auth/resolve.ts";
import type { ActiveSupport } from "./support.ts";

/**
 * `active`: the session is valid. `expired`: the cookie's token expired and the
 * route may not refresh it; the next navigation through the proxy does. `ended`
 * and `banned`: Auth ended the session or banned the user, and the cookies are
 * cleared. `signed_out`: no user session.
 */
export type SessionWatchStatus =
  | "active"
  | "expired"
  | "ended"
  | "banned"
  | "signed_out";

/** The JSON `sessionStatusRoute` answers with. */
export interface SessionStatusBody {
  readonly status: SessionWatchStatus;
  /** The signed-in user (the admin in a support session). */
  readonly userId: string | null;
  /**
   * SHA-256 (hex) of the claims that decide access and of the support session,
   * so a role, tenant or support target change gives a new value. `null` when
   * there is no active session.
   */
  readonly fingerprint: string | null;
  /** Seconds since epoch, from the token's `exp`. */
  readonly expiresAt: number | null;
  /** The running support session, when the admin views the app as a user. */
  readonly support: {
    readonly sessionId: string;
    readonly targetUserId: string;
    readonly readOnly: boolean;
  } | null;
}

/**
 * The part of a server `sessionStatusRoute` uses: `createServer`, `createNext`
 * and the other adapters fit.
 */
export interface SessionStatusServer {
  resolve(
    request: Request,
    options?: { readonly refresh?: boolean; readonly verifySession?: boolean },
  ): Promise<AuthResolution>;
  readonly support: {
    current(
      request: Request,
      auth: AuthState,
    ): Promise<ActiveSupport | undefined>;
  };
}

export interface SessionStatusRouteOptions {
  /**
   * Ask Auth whether the session still exists, one network call per check, so a
   * revoked session or a ban shows up before the token expires. Defaults to
   * false: the route reads the verified claims only, and the proxy's
   * `verifySession` and the `authz:<uid>` broadcast catch revocations.
   */
  readonly verifySession?: boolean;
  /**
   * Refresh an expiring session cookie and send the new cookies. Defaults to
   * false: the proxy refreshes, and an expired token answers `expired`.
   */
  readonly refresh?: boolean;
  /**
   * Claims left out of the fingerprint besides the ones that change on every
   * refresh (`exp`, `iat`, `nbf`, `jti`).
   */
  readonly ignoreClaims?: readonly string[];
}

const VOLATILE_CLAIMS = ["exp", "iat", "nbf", "jti"];

const HEADERS = {
  "content-type": "application/json",
  "cache-control": "no-store, private",
};

/** JSON with object keys sorted at every level, so equal claims hash alike. */
function canonical(value: unknown): string {
  if (value === undefined) {
    return "null";
  }

  if (Array.isArray(value)) {
    return `[${value.map(canonical).join(",")}]`;
  }

  if (value !== null && typeof value === "object") {
    const entries = Object.entries(value)
      .filter(([, each]) => each !== undefined)
      .toSorted(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));

    return `{${entries.map(([key, each]) => `${JSON.stringify(key)}:${canonical(each)}`).join(",")}}`;
  }

  return JSON.stringify(value);
}

async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(text),
  );

  return Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
}

/**
 * The fingerprint `sessionStatusRoute` reports for a user's claims and support
 * session: a SHA-256 hex digest that changes when a claim that decides access
 * changes (role, tenant, memberships, `aal`) or the support target does.
 */
export async function claimsFingerprint(
  claims: Readonly<Record<string, unknown>>,
  support?: ActiveSupport,
  ignore: readonly string[] = [],
): Promise<string> {
  const skip = new Set([...VOLATILE_CLAIMS, ...ignore]);

  const kept = Object.fromEntries(
    Object.entries(claims).filter(([key]) => !skip.has(key)),
  );

  return sha256Hex(
    canonical({
      claims: kept,
      support: support
        ? {
            session: support.session.id,
            target: support.session.targetUserId,
            readOnly: support.session.readOnly,
          }
        : null,
    }),
  );
}

const statusOf = (resolution: AuthResolution): SessionWatchStatus => {
  if (resolution.sessionVerified === false) {
    return resolution.reason === "user_banned" ? "banned" : "ended";
  }

  const { auth } = resolution;

  if (auth.kind === "user") {
    return "active";
  }

  return auth.kind === "none" && auth.reason === "expired"
    ? "expired"
    : "signed_out";
};

/**
 * A `GET` handler that tells a browser whether its session still holds, for
 * apps that keep the session in httpOnly cookies and have no browser Supabase
 * client: `useSessionWatch()` from `better-supabase/next/client` polls it. It
 * answers `{ status, userId, fingerprint, expiresAt, support }` with
 * `Cache-Control: no-store`.
 *
 * ```ts
 * // app/api/session-status/route.ts
 * export const GET = sessionStatusRoute(bsb);
 * ```
 */
export function sessionStatusRoute(
  server: SessionStatusServer,
  options: SessionStatusRouteOptions = {},
): (request: Request) => Promise<Response> {
  const verifySession = options.verifySession ?? false;
  const refresh = options.refresh ?? false;

  return async (request) => {
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response(null, {
        status: 405,
        headers: { allow: "GET, HEAD" },
      });
    }

    const resolution = await server.resolve(request, {
      verifySession,
      refresh,
    });

    const status = statusOf(resolution);
    const { auth } = resolution;
    const user = auth.kind === "user" ? auth : undefined;

    const support =
      user && status === "active"
        ? await server.support.current(request, user)
        : undefined;

    const body: SessionStatusBody = {
      status,
      userId: user?.user.id ?? null,
      fingerprint:
        user && status === "active"
          ? await claimsFingerprint(user.claims, support, options.ignoreClaims)
          : null,
      expiresAt: user?.expiresAt ?? null,
      support: support
        ? {
            sessionId: support.session.id,
            targetUserId: support.session.targetUserId,
            readOnly: support.session.readOnly,
          }
        : null,
    };

    return resolution.apply(
      new Response(request.method === "HEAD" ? null : JSON.stringify(body), {
        status: 200,
        headers: HEADERS,
      }),
    );
  };
}
