import type { FlagValue } from "../blocks/flags/flags.ts";

import { FLAG_OVERRIDES_COOKIE } from "../flags-sdk/cookie.ts";

export interface FlagOverrideCookieOptions {
  /**
   * Encrypts the values, such as `encryptOverrides` from `flags`, for an app
   * that reads the cookie encrypted. Without it the cookie holds plaintext
   * JSON, which `explorerOverrides()` reads without a `decrypt`.
   */
  readonly encrypt?: (
    values: Readonly<Record<string, FlagValue>>,
  ) => Promise<string>;
}

export interface FlagOverrideCookie {
  readonly name: typeof FLAG_OVERRIDES_COOKIE;
  readonly value: string;
  /** `name=value`, for a `cookie` request header. */
  readonly header: string;
}

/**
 * The `vercel-flag-overrides` cookie Flags Explorer would set, so a test serves
 * chosen variants without the toolbar: pass it to `context.addCookies()` in
 * Playwright or as a request's `cookie` header.
 */
export async function flagOverrideCookie(
  values: Readonly<Record<string, FlagValue>>,
  options: FlagOverrideCookieOptions = {},
): Promise<FlagOverrideCookie> {
  const value = options.encrypt
    ? await options.encrypt(values)
    : encodeURIComponent(JSON.stringify(values));

  return {
    name: FLAG_OVERRIDES_COOKIE,
    value,
    header: `${FLAG_OVERRIDES_COOKIE}=${value}`,
  };
}
