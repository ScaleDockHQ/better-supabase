import type { SupportView } from "../auth/support-view.ts";
import type { AuthSession } from "../auth/view.ts";
import type { QuerySpec } from "../core/spec.ts";
import type { LiveCountSeed } from "../realtime/live.ts";
import type {
  ActionForm,
  ActionHandle,
  ActionInputOf,
  ActionResultOf,
  BetterHooks,
  ClientLike,
  LiveCount,
  LiveCountHookOptions,
  UseActionFormOptions,
  UseActionOptions,
} from "./index.ts";

export {
  BetterSupabaseProvider,
  useAuth,
  useBroadcast,
  useLiveQuery,
  useSupabase,
} from "./index.ts";
// Kept external by tsdown so it stays a `'use client'` module: a Server
// Component layout can render it and pass the session promise across.
export { SessionProvider } from "./session.js";
export { fieldErrorsOf } from "./field-errors.ts";
export { tenantOf } from "../auth/tenant.ts";
export type {
  ActionForm,
  ActionHandle,
  ActionInputOf,
  ActionResultOf,
  UseActionFormOptions,
  UseActionOptions,
} from "./index.ts";
export type {
  BetterHooks,
  BetterSupabaseProviderProps,
  BroadcastOptions,
  ClientLike,
  ClaimsOf,
  LiveCount,
  LiveCountHookOptions,
  LiveQueryHookOptions,
  ProfileOf,
} from "./index.ts";
export type { SessionProviderProps } from "./session.ts";
export type { AuthSession } from "../auth/view.ts";
export type { SupportView } from "../auth/support-view.ts";
export { supportOf } from "../auth/support-view.ts";
export type { Impersonator } from "../auth/impersonation.ts";
export type { MembershipClaim } from "../auth/entitlements.ts";
export type { LiveCountSeed } from "../realtime/live.ts";

function clientOnly(name: string): () => never {
  return () => {
    throw new Error(
      `better-supabase: ${name}() runs in Client Components only. In Server Components use \`bs.context()\` or \`db.$run(spec)\`.`,
    );
  };
}

/** The `react-server` build of `useSession`: await `bs.session()` instead. */
export const useSession: <C = unknown, P = unknown>() => AuthSession<C, P> =
  clientOnly("useSession");

/** The `react-server` build of `useSupportSession`: use `supportOf(await bs.session())` instead. */
export const useSupportSession: () => SupportView | undefined =
  clientOnly("useSupportSession");

/** The `react-server` build of `useLiveCount`: render the `bs.liveCount()` seed instead. */
export const useLiveCount: (
  source: QuerySpec<string, "count", number> | LiveCountSeed | null | undefined,
  options?: LiveCountHookOptions,
) => LiveCount = clientOnly("useLiveCount");

/** The `react-server` build of `useAction`: call the Server Action directly instead. */
export const useAction: <I, T>(
  action: (input: I) => Promise<ActionResultOf<T>>,
  options?: UseActionOptions<ActionInputOf<I>, T>,
) => ActionHandle<ActionInputOf<I>, T> = clientOnly("useAction");

/** The `react-server` build of `useActionForm`: render the form in a Client Component. */
export const useActionForm: <T>(
  action: (input: FormData) => Promise<ActionResultOf<T>>,
  options?: UseActionFormOptions<T>,
) => ActionForm<T> = clientOnly("useActionForm");

/**
 * The `react-server` build of `createHooks`: importing a module that creates
 * hooks is safe on the server, calling a hook there throws.
 */
export function createHooks<B extends ClientLike>(): BetterHooks<B> {
  return {
    useDb: clientOnly("useDb"),
    useQueries: clientOnly("useQueries"),
    useSupabase: clientOnly("useSupabase"),
    useAuth: clientOnly("useAuth"),
    useSession: clientOnly("useSession"),
  };
}
