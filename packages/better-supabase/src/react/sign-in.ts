"use client";

import type {
  AuthError,
  Provider,
  SignInWithOAuthCredentials,
  SignInWithPasswordlessCredentials,
  SupabaseClient,
  VerifyOtpParams,
} from "@supabase/supabase-js";

import { useContext, useMemo, useRef, useState } from "react";

import { ClientContext } from "./hooks.ts";

type AuthApi = Pick<
  SupabaseClient["auth"],
  | "signInWithPassword"
  | "signInWithOtp"
  | "verifyOtp"
  | "signInWithOAuth"
  | "signOut"
>;

export interface AuthHookOptions {
  /** A supabase-js client for apps without `<BetterSupabaseProvider>`. */
  readonly client?: { readonly auth: AuthApi };
  /** Called after a call succeeds, e.g. to navigate. */
  readonly onSuccess?: () => void;
}

export interface PendingState {
  /** A call is in flight. */
  readonly pending: boolean;
  /** The last call's error; cleared when the next call starts. */
  readonly error: AuthError | undefined;
}

export interface SignIn extends PendingState {
  readonly password: (credentials: {
    readonly email: string;
    readonly password: string;
  }) => Promise<AuthError | undefined>;
  /** Sends a magic link or a one-time code to an email or a phone. */
  readonly otp: (
    credentials: SignInWithPasswordlessCredentials,
  ) => Promise<AuthError | undefined>;
  /** Checks the code `otp` sent. */
  readonly verifyOtp: (
    params: VerifyOtpParams,
  ) => Promise<AuthError | undefined>;
  /** Starts the OAuth redirect. In a browser the page navigates away. */
  readonly oauth: (
    provider: Provider,
    options?: SignInWithOAuthCredentials["options"],
  ) => Promise<AuthError | undefined>;
}

export interface SignOut extends PendingState {
  readonly signOut: (options?: {
    readonly scope?: "global" | "local" | "others";
  }) => Promise<AuthError | undefined>;
}

function useAuthApi(options: AuthHookOptions, hook: string): AuthApi {
  const context = useContext(ClientContext);
  const auth = options.client?.auth ?? context?.client.supabase.auth;
  if (!auth) {
    throw new Error(
      `better-supabase: ${hook} needs <BetterSupabaseProvider client={bs}> or { client: supabase }`,
    );
  }
  return auth;
}

/** Runs auth calls with `pending` and `error` state; the latest call owns the state. */
function usePending(options: AuthHookOptions): {
  readonly state: PendingState;
  readonly run: (
    call: () => Promise<{ readonly error: AuthError | null }>,
  ) => Promise<AuthError | undefined>;
} {
  const [state, setState] = useState<PendingState>({
    pending: false,
    error: undefined,
  });
  const latest = useRef({ call: 0, options });
  // oxlint-disable-next-line react/refs -- latest-ref pattern; the react peer range predates useEffectEvent.
  latest.current.options = options;
  const run = useMemo(
    () => async (call: () => Promise<{ readonly error: AuthError | null }>) => {
      latest.current.call += 1;
      const id = latest.current.call;
      setState({ pending: true, error: undefined });
      let error: AuthError | null;
      try {
        ({ error } = await call());
      } catch (cause) {
        if (id === latest.current.call)
          setState({ pending: false, error: undefined });
        throw cause;
      }
      if (id === latest.current.call)
        setState({ pending: false, error: error ?? undefined });
      if (!error) latest.current.options.onSuccess?.();
      return error ?? undefined;
    },
    [],
  );
  return { state, run };
}

/**
 * Sign-in calls with `pending` and `error` state. The session lands in the
 * client's auth store, so `useAuth()` updates on its own.
 *
 * ```tsx
 * const signIn = useSignIn({ onSuccess: () => router.push('/') });
 * <button disabled={signIn.pending} onClick={() => signIn.password({ email, password })} />
 * ```
 */
export function useSignIn(options: AuthHookOptions = {}): SignIn {
  const auth = useAuthApi(options, "useSignIn");
  const { state, run } = usePending(options);
  const calls = useMemo(
    () => ({
      password: (credentials: {
        readonly email: string;
        readonly password: string;
      }) => run(() => auth.signInWithPassword({ ...credentials })),
      otp: (credentials: SignInWithPasswordlessCredentials) =>
        run(() => auth.signInWithOtp(credentials)),
      verifyOtp: (params: VerifyOtpParams) => run(() => auth.verifyOtp(params)),
      oauth: (
        provider: Provider,
        oauthOptions?: SignInWithOAuthCredentials["options"],
      ) =>
        run(() =>
          auth.signInWithOAuth(
            oauthOptions ? { provider, options: oauthOptions } : { provider },
          ),
        ),
    }),
    [auth, run],
  );
  return { ...state, ...calls };
}

/** `auth.signOut()` with `pending` and `error` state. The provider clears cached queries. */
export function useSignOut(options: AuthHookOptions = {}): SignOut {
  const auth = useAuthApi(options, "useSignOut");
  const { state, run } = usePending(options);
  const signOut = useMemo(
    () =>
      (signOutOptions?: { readonly scope?: "global" | "local" | "others" }) =>
        run(() =>
          auth.signOut(signOutOptions ? { ...signOutOptions } : undefined),
        ),
    [auth, run],
  );
  return { ...state, signOut };
}
