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
export { SessionProvider, useSession } from "./session.ts";
export type { SessionProviderProps } from "./session.ts";
export type { AuthSession } from "../auth/view.ts";
export type { Impersonator } from "../auth/impersonation.ts";
export { hasEntitlement } from "../auth/entitlements.ts";
export type { EntitlementKey, MembershipClaim } from "../auth/entitlements.ts";
export type { LiveCountSeed } from "../realtime/live.ts";
