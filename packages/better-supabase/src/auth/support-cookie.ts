import type { SupportSession } from "./support.ts";

/** The cookie that carries the support session id. */
export const SUPPORT_COOKIE = "bs-support";

export interface SupportCookieOptions {
  /** Defaults to `bs-support`. */
  readonly name?: string;
  /** Defaults to `/`. */
  readonly path?: string;
  /** Defaults to true; set false for plain-HTTP local development. */
  readonly secure?: boolean;
}

/** `Set-Cookie` for a session: HttpOnly, SameSite=Lax, gone when the session expires. */
export function supportCookie(
  session: Pick<SupportSession, "id" | "expiresAt">,
  options: SupportCookieOptions = {},
  now: number = Date.now(),
): string {
  const maxAge = Math.max(
    0,
    Math.ceil((session.expiresAt.epochMilliseconds - now) / 1000),
  );
  return cookieLine(options, encodeURIComponent(session.id), maxAge);
}

/** `Set-Cookie` that removes the support cookie. */
export function clearSupportCookie(options: SupportCookieOptions = {}): string {
  return cookieLine(options, "", 0);
}

function cookieLine(
  options: SupportCookieOptions,
  value: string,
  maxAge: number,
): string {
  return [
    `${options.name ?? SUPPORT_COOKIE}=${value}`,
    `Path=${options.path ?? "/"}`,
    `Max-Age=${String(maxAge)}`,
    "HttpOnly",
    "SameSite=Lax",
    ...(options.secure === false ? [] : ["Secure"]),
  ].join("; ");
}

/** The support session id in a `Cookie` header, or `undefined`. */
export function supportCookieValue(
  cookieHeader: string | null,
  name: string = SUPPORT_COOKIE,
): string | undefined {
  if (!cookieHeader) return undefined;
  for (const part of cookieHeader.split(";")) {
    const index = part.indexOf("=");
    if (index === -1 || part.slice(0, index).trim() !== name) continue;
    const value = decodeURIComponent(part.slice(index + 1).trim());
    return value === "" ? undefined : value;
  }
  return undefined;
}
