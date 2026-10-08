import type { Provider } from "@supabase/supabase-js";
import type { ReactNode } from "react";

import { useContext, useEffect, useMemo, useRef, useState } from "react";

import type { AuthSnapshot } from "../../client/index.ts";
import type {
  AuthFailure,
  AuthLinkClient,
  AuthLinkResult,
  OAuthClient,
  OAuthSignInOptions,
  WebBrowserLike,
} from "../../client/native/auth-link.ts";
import type { PendingState } from "../sign-in.ts";

import {
  handleAuthDeepLink,
  signInWithOAuthBrowser,
} from "../../client/native/auth-link.ts";
import { ClientContext, useAuth } from "../hooks.ts";
import { usePending } from "../sign-in.ts";

export type {
  AuthFailure,
  AuthLinkResult,
  OAuthSignInOptions,
  WebBrowserLike,
} from "../../client/native/auth-link.ts";

interface IdTokenClient {
  readonly auth: {
    signInWithIdToken(credentials: {
      provider: string;
      token: string;
      nonce?: string;
      access_token?: string;
    }): Promise<{ readonly error: AuthFailure | null }>;
  };
}

export interface UseOAuthOptions extends OAuthSignInOptions {
  /** `expo-web-browser`. */
  readonly browser: WebBrowserLike;
  /** A supabase-js client for apps without `<BetterSupabaseProvider>`. */
  readonly client?: OAuthClient & IdTokenClient;
  readonly onSuccess?: () => void;
}

export interface OAuth extends PendingState {
  /** Opens the provider in an auth session and finishes the sign-in. A cancelled browser is no error. */
  readonly signIn: (provider: Provider) => Promise<AuthFailure | undefined>;
  /**
   * Native sign-in with an ID token from `expo-apple-authentication` or
   * `@react-native-google-signin/google-signin`.
   */
  readonly idToken: (credentials: {
    readonly provider: "apple" | "google" | (string & {});
    readonly token: string;
    readonly nonce?: string;
    readonly accessToken?: string;
  }) => Promise<AuthFailure | undefined>;
}

function useClientOf<C>(explicit: C | undefined, hook: string): C {
  const context = useContext(ClientContext);
  // SAFETY: the provider's supabase-js client has every auth method the
  // structural client types name.
  const client = explicit ?? (context?.client.supabase as C | undefined);
  if (!client) {
    throw new Error(
      `better-supabase: ${hook} needs <BetterSupabaseProvider client={bs}> or { client: supabase }`,
    );
  }
  return client;
}

const NOT_FINISHED = { error: null };

/**
 * OAuth and native ID-token sign-in on a device, with `pending` and
 * `error` state.
 *
 * ```tsx
 * import * as WebBrowser from 'expo-web-browser';
 * const oauth = useOAuth({ browser: WebBrowser, redirectTo: Linking.createURL('auth/callback') });
 * <Button title="GitHub" disabled={oauth.pending} onPress={() => oauth.signIn('github')} />
 * ```
 */
export function useOAuth(options: UseOAuthOptions): OAuth {
  const client = useClientOf(options.client, "useOAuth");
  const { state, run } = usePending(options);
  const latest = useRef(options);
  // oxlint-disable-next-line react/refs -- latest-ref pattern; the react peer range predates useEffectEvent.
  latest.current = options;
  const calls = useMemo(
    () => ({
      signIn: (provider: Provider) =>
        run(async () => {
          const { browser, redirectTo, scopes, queryParams } = latest.current;
          const result = await signInWithOAuthBrowser(
            client,
            browser,
            provider,
            {
              redirectTo,
              ...(scopes ? { scopes } : {}),
              ...(queryParams ? { queryParams } : {}),
            },
          );
          if (result.type === "error") return { error: result.error };
          return NOT_FINISHED;
        }),
      idToken: (credentials: {
        readonly provider: string;
        readonly token: string;
        readonly nonce?: string;
        readonly accessToken?: string;
      }) =>
        run(() =>
          client.auth.signInWithIdToken({
            provider: credentials.provider,
            token: credentials.token,
            ...(credentials.nonce ? { nonce: credentials.nonce } : {}),
            ...(credentials.accessToken
              ? { access_token: credentials.accessToken }
              : {}),
          }),
        ),
    }),
    [client, run],
  );
  return { ...state, ...calls };
}

/** The part of React Native's `Linking` that `useAuthDeepLinks` uses. */
export interface LinkingLike {
  getInitialURL(): Promise<string | null>;
  addEventListener(
    type: "url",
    listener: (event: { readonly url: string }) => void,
  ): { remove(): void };
}

export interface AuthDeepLinksOptions {
  readonly client?: AuthLinkClient;
  /** Called with each auth link's outcome, e.g. to navigate after a magic link. */
  readonly onResult?: (
    result: Exclude<AuthLinkResult, { type: "none" }>,
  ) => void;
}

/**
 * Finishes sign-ins from deep links while mounted: the URL that opened the
 * app and every link after it (magic links, email confirmations, OAuth
 * redirects outside an auth session). Returns the last auth link's outcome.
 *
 * ```tsx
 * import * as Linking from 'expo-linking';
 * useAuthDeepLinks(Linking, { onResult: (r) => r.type === 'signed-in' && router.replace('/') });
 * ```
 */
export function useAuthDeepLinks(
  linking: LinkingLike,
  options: AuthDeepLinksOptions = {},
): AuthLinkResult {
  const client = useClientOf(options.client, "useAuthDeepLinks");
  const [last, setLast] = useState<AuthLinkResult>({ type: "none" });
  const latest = useRef(options);
  // oxlint-disable-next-line react/refs -- latest-ref pattern; the react peer range predates useEffectEvent.
  latest.current = options;

  useEffect(() => {
    let active = true;
    const seen = new Set<string>();
    const handle = (url: string | null) => {
      if (!url || seen.has(url)) return;
      seen.add(url);
      void handleAuthDeepLink(client, url).then((result) => {
        if (!active || result.type === "none") return;
        setLast(result);
        latest.current.onResult?.(result);
      });
    };
    void linking.getInitialURL().then(handle);
    const subscription = linking.addEventListener("url", ({ url }) => {
      handle(url);
    });
    return () => {
      active = false;
      subscription.remove();
    };
  }, [client, linking]);

  return last;
}

export interface ProtectedRouteOptions {
  /** `useSegments()` from expo-router. */
  readonly segments: readonly string[];
  /** `useRouter()` from expo-router. */
  readonly router: { replace(href: string): void };
  /** The route group signed-out users may see. Defaults to `(auth)`. */
  readonly publicGroup?: string;
  /** Defaults to `/sign-in`. */
  readonly signInHref?: string;
  /** Where a signed-in user on a public screen goes. Defaults to `/`. */
  readonly homeHref?: string;
}

/**
 * Redirects with expo-router: signed-out users outside the public group go
 * to `signInHref`, signed-in users inside it go to `homeHref`. Returns the
 * auth state; render a splash screen while it is `loading`.
 *
 * ```tsx
 * const status = useProtectedRoute({ segments: useSegments(), router: useRouter() });
 * ```
 */
export function useProtectedRoute(
  options: ProtectedRouteOptions,
): AuthSnapshot["status"] {
  const { status } = useAuth();
  const { segments, router } = options;
  const group = options.publicGroup ?? "(auth)";
  const signInHref = options.signInHref ?? "/sign-in";
  const homeHref = options.homeHref ?? "/";
  const isPublic = segments[0] === group;

  useEffect(() => {
    if (status === "loading") return;
    if (status === "signed-out" && !isPublic) router.replace(signInHref);
    else if (status === "signed-in" && isPublic) router.replace(homeHref);
  }, [status, isPublic, router, signInHref, homeHref]);

  return status;
}

export interface AuthGateProps {
  /** Shown while the session loads. Defaults to nothing. */
  readonly fallback?: ReactNode;
  /** Shown to signed-out users, e.g. the sign-in screen. */
  readonly signedOut?: ReactNode;
  readonly children?: ReactNode;
}

/**
 * Renders `children` for signed-in users, `signedOut` otherwise, and
 * `fallback` while the session loads. With expo-router, `Stack.Protected`
 * takes `useAuth().status === 'signed-in'` as its `guard` instead.
 */
export function AuthGate(props: AuthGateProps): ReactNode {
  const { status } = useAuth();
  if (status === "loading") return props.fallback ?? null;
  if (status === "signed-out") return props.signedOut ?? null;
  return props.children ?? null;
}
