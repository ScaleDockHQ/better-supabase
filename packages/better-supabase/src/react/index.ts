"use client";

export {
  BetterSupabaseProvider,
  createHooks,
  useAuth,
  useBroadcast,
  useLiveCount,
  useLiveQuery,
  useSupabase,
} from "./hooks.ts";
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
} from "./hooks.ts";
export { useNotifications } from "./notifications.ts";
export type {
  NotificationSource,
  NotificationsState,
  UseNotificationsOptions,
} from "./notifications.ts";
export { SessionProvider, useSession, useSupportSession } from "./session.ts";
export type { SessionProviderProps } from "./session.ts";
export type { AuthSession } from "../auth/view.ts";
export type { SupportView } from "../auth/support-view.ts";
export { supportOf } from "../auth/support-view.ts";
export type { Impersonator } from "../auth/impersonation.ts";
export { hasEntitlement } from "../auth/entitlements.ts";
export type { EntitlementKey, MembershipClaim } from "../auth/entitlements.ts";
export type { LiveCountSeed } from "../realtime/live.ts";
