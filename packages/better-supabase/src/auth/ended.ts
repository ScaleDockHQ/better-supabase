import { extractCredentials } from "@supabase/server/core";

import { decodeJwtPayload } from "../core/base64.ts";
import {
  AUTH_CACHE_HEADERS,
  type CookieOptions,
  parseCookies,
  readSession,
  serializeCookie,
  sessionCookieName,
  writeSession,
} from "./session.ts";

export type SessionStatus = "active" | "ended" | "unknown";

export interface SessionStatusOptions {
  readonly url: string;
  readonly publishableKey: string;
  readonly cookieName?: string;
  readonly fetch?: typeof fetch;
  readonly timeoutMs?: number;
  readonly now?: () => number;
}

export interface ClearSessionCookiesOptions {
  readonly url: string;
  readonly cookieName?: string;
  readonly cookie?: CookieOptions;
}

const DEFAULT_TIMEOUT_MS = 5000;

function accessTokenOf(
  request: Request,
  options: SessionStatusOptions,
): string | undefined {
  const bearer = extractCredentials(request).token;
  if (bearer) return bearer;
  const session = readSession(
    parseCookies(request.headers.get("cookie")),
    options.cookieName ?? sessionCookieName(options.url),
  );
  return session?.access_token;
}

export async function sessionStatus(
  input: Request | string,
  options: SessionStatusOptions,
): Promise<SessionStatus> {
  const token =
    typeof input === "string" ? input : accessTokenOf(input, options);
  if (!token) return "unknown";
  const exp = decodeJwtPayload(token)?.["exp"];
  if (typeof exp === "number" && exp * 1000 <= (options.now ?? Date.now)())
    return "unknown";
  const doFetch = options.fetch ?? fetch;
  try {
    const response = await doFetch(`${options.url}/auth/v1/user`, {
      headers: {
        apikey: options.publishableKey,
        authorization: `Bearer ${token}`,
      },
      signal: AbortSignal.timeout(options.timeoutMs ?? DEFAULT_TIMEOUT_MS),
    });
    await response.body?.cancel();
    if (response.status === 401 || response.status === 403) return "ended";
    return response.ok ? "active" : "unknown";
  } catch {
    return "unknown";
  }
}

export function clearSessionCookies<R extends Response>(
  request: Request,
  response: R,
  options: ClearSessionCookiesOptions,
): R {
  const writes = writeSession(
    parseCookies(request.headers.get("cookie")),
    options.cookieName ?? sessionCookieName(options.url),
    null,
    options.cookie,
  );
  if (writes.length === 0) return response;
  for (const write of writes)
    response.headers.append("set-cookie", serializeCookie(write));
  for (const [key, value] of Object.entries(AUTH_CACHE_HEADERS))
    response.headers.set(key, value);
  return response;
}
