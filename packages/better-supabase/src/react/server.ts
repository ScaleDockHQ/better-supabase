import type { AuthSession, SupportView } from "../auth/view.ts";
import type { QuerySpec } from "../core/spec.ts";
import type { LiveCountSeed } from "../realtime/live.ts";
import type {
  BetterHooks,
  ClientLike,
  LiveCount,
  LiveCountHookOptions,
} from "./index.ts";
import type {
  NotificationsState,
  UseNotificationsOptions,
} from "./notifications.ts";

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
export type {
  NotificationSource,
  NotificationsState,
  UseNotificationsOptions,
} from "./notifications.ts";
export type { SessionProviderProps } from "./session.ts";
export type { AuthSession, SupportView } from "../auth/view.ts";
export { supportOf } from "../auth/view.ts";
export type { Impersonator } from "../auth/impersonation.ts";
export { hasEntitlement } from "../auth/entitlements.ts";
export type { EntitlementKey, MembershipClaim } from "../auth/entitlements.ts";
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

/** The `react-server` build of `useNotifications`: call `notifications.list()` instead. */
export const useNotifications: <T>(
  options: UseNotificationsOptions<T>,
) => NotificationsState<T> = clientOnly("useNotifications");

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
