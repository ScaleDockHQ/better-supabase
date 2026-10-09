import type { Provider } from "@supabase/supabase-js";

/** An auth error: supabase-js `AuthError`s and the errors a link carries. */
export interface AuthFailure {
  readonly message: string;
  readonly code?: string | undefined;
  readonly status?: number | undefined;
}

interface AuthReply {
  readonly error: AuthFailure | null;
}

/** The part of a supabase-js client the deep-link helpers call. */
export interface AuthLinkClient {
  readonly auth: {
    exchangeCodeForSession(code: string): Promise<AuthReply>;
    setSession(tokens: {
      access_token: string;
      refresh_token: string;
    }): Promise<AuthReply>;
    verifyOtp(params: {
      token_hash: string;
      type:
        | "signup"
        | "invite"
        | "magiclink"
        | "recovery"
        | "email_change"
        | "email";
    }): Promise<AuthReply>;
  };
}

/** What a link did: nothing (not an auth link), a session, or an error. */
export type AuthLinkResult =
  | { readonly type: "none" }
  | { readonly type: "signed-in"; readonly via: "code" | "tokens" | "otp" }
  | { readonly type: "error"; readonly error: AuthFailure };

const OTP_TYPES = new Set([
  "signup",
  "invite",
  "magiclink",
  "recovery",
  "email_change",
  "email",
]);

type OtpType = Parameters<AuthLinkClient["auth"]["verifyOtp"]>[0]["type"];

function isOtpType(value: string): value is OtpType {
  return OTP_TYPES.has(value);
}

/**
 * The query and fragment parameters of a URL. Parsed by hand: Hermes'
 * `URL` and `URLSearchParams` leave parts unimplemented.
 */
export function linkParams(url: string): ReadonlyMap<string, string> {
  const params = new Map<string, string>();
  const hash = url.indexOf("#");
  const query = url.indexOf("?");
  const parts = [
    query === -1 ? "" : url.slice(query + 1, hash > query ? hash : undefined),
    hash === -1 ? "" : url.slice(hash + 1),
  ];
  for (const part of parts) {
    for (const pair of part.split("&")) {
      if (pair === "") continue;
      const at = pair.indexOf("=");
      const name = at === -1 ? pair : pair.slice(0, at);
      const value = at === -1 ? "" : pair.slice(at + 1);
      try {
        params.set(
          decodeURIComponent(name.replaceAll("+", " ")),
          decodeURIComponent(value.replaceAll("+", " ")),
        );
      } catch {
        // a malformed escape leaves the pair out
      }
    }
  }
  return params;
}

const settle = async (
  reply: Promise<AuthReply>,
  via: "code" | "tokens" | "otp",
): Promise<AuthLinkResult> => {
  const { error } = await reply;
  return error ? { type: "error", error } : { type: "signed-in", via };
};

/**
 * Finishes a sign-in from a deep link: an OAuth or PKCE `code`, implicit
 * flow tokens in the fragment, or a magic link's `token_hash`. Returns
 * `none` for links that carry none of them, so it can see every URL.
 *
 * ```ts
 * Linking.addEventListener('url', ({ url }) => void handleAuthDeepLink(supabase, url));
 * ```
 */
export function handleAuthDeepLink(
  supabase: AuthLinkClient,
  url: string,
): Promise<AuthLinkResult> {
  const params = linkParams(url);
  const failure = params.get("error_description") ?? params.get("error");
  if (failure !== undefined) {
    const code = params.get("error_code") ?? params.get("error");
    return Promise.resolve({
      type: "error",
      error: { message: failure, ...(code ? { code } : {}) },
    });
  }
  const code = params.get("code");
  if (code) return settle(supabase.auth.exchangeCodeForSession(code), "code");
  const access = params.get("access_token");
  const refresh = params.get("refresh_token");
  if (access && refresh) {
    return settle(
      supabase.auth.setSession({
        access_token: access,
        refresh_token: refresh,
      }),
      "tokens",
    );
  }
  const tokenHash = params.get("token_hash");
  const type = params.get("type");
  if (tokenHash && type && isOtpType(type))
    return settle(
      supabase.auth.verifyOtp({ token_hash: tokenHash, type }),
      "otp",
    );
  return Promise.resolve({ type: "none" });
}

/** The part of `expo-web-browser` OAuth sign-in uses. */
export interface WebBrowserLike {
  openAuthSessionAsync(
    url: string,
    redirectUrl?: string | null,
  ): Promise<{ readonly type: string; readonly url?: string }>;
}

/** The part of a supabase-js client OAuth sign-in calls. */
export interface OAuthClient extends AuthLinkClient {
  readonly auth: AuthLinkClient["auth"] & {
    signInWithOAuth(credentials: {
      provider: Provider;
      options: {
        redirectTo: string;
        skipBrowserRedirect: true;
        scopes?: string;
        queryParams?: Record<string, string>;
      };
    }): Promise<{
      readonly data: { readonly url: string | null } | { readonly url?: null };
      readonly error: AuthFailure | null;
    }>;
  };
}

export interface OAuthSignInOptions {
  /** The app's deep link back, e.g. `Linking.createURL('auth/callback')`. Add it to the redirect allow list. */
  readonly redirectTo: string;
  readonly scopes?: string;
  readonly queryParams?: Readonly<Record<string, string>>;
}

/**
 * OAuth on a device: opens the provider in an auth session, then finishes
 * the sign-in from the redirect. A cancelled or dismissed browser returns
 * `none`.
 *
 * ```ts
 * import * as WebBrowser from 'expo-web-browser';
 * await signInWithOAuthBrowser(supabase, WebBrowser, 'github', { redirectTo: Linking.createURL('auth/callback') });
 * ```
 */
export async function signInWithOAuthBrowser(
  supabase: OAuthClient,
  browser: WebBrowserLike,
  provider: Provider,
  options: OAuthSignInOptions,
): Promise<AuthLinkResult> {
  const { data, error } = await supabase.auth.signInWithOAuth({
    provider,
    options: {
      redirectTo: options.redirectTo,
      skipBrowserRedirect: true,
      ...(options.scopes ? { scopes: options.scopes } : {}),
      ...(options.queryParams
        ? { queryParams: { ...options.queryParams } }
        : {}),
    },
  });
  if (error) return { type: "error", error };
  if (!data.url)
    return { type: "error", error: { message: "No OAuth URL was returned" } };
  const session = await browser.openAuthSessionAsync(
    data.url,
    options.redirectTo,
  );
  if (session.type !== "success" || !session.url) return { type: "none" };
  return handleAuthDeepLink(supabase, session.url);
}
