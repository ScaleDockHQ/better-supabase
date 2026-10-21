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

export { useAction, useActionForm } from "./actions.ts";

export {
  useBlockEvent,
  useBlockMutation,
  useBlockQuery,
} from "./block-hooks.ts";

export type {
  BlockEventSource,
  BlockMutationActions,
  BlockMutationState,
  BlockQueryActions,
  BlockQueryOptions,
  BlockQueryState,
  BlockRefetchOn,
} from "../blocks/block-controller.ts";

export { fieldErrorsOf } from "../bindings/field-errors.ts";

export { tenantOf } from "../auth/tenant.ts";

export type {
  ActionForm,
  ActionHandle,
  ActionInputOf,
  ActionResultOf,
  UseActionFormOptions,
  UseActionOptions,
} from "./actions.ts";

export { SessionProvider, useSession, useSupportSession } from "./session.ts";

export { usePresence } from "./presence.ts";

export type {
  Presence,
  PresenceHookOptions,
  PresenceTopic,
} from "./presence.ts";

export { useSignIn, useSignOut } from "./sign-in.ts";

export type {
  AuthHookOptions,
  PendingState,
  SignIn,
  SignOut,
} from "./sign-in.ts";

export { useDebouncedSearch } from "./search.ts";

export type { DebouncedSearch, DebouncedSearchOptions } from "./search.ts";

export { useImage, useSignedUrl, useUpload } from "./storage.ts";

export type {
  ImageSource,
  SignedUrl,
  SignedUrlSource,
  StorageImage,
  UseImageOptions,
  Upload,
  UploadStatus,
  UploadTarget,
  UseUploadOptions,
} from "./storage.ts";

export { escapeLike } from "../ir/escape-like.ts";

export type { SessionProviderProps } from "./session.ts";

export type { AuthSession } from "../auth/view.ts";

export type { SupportView } from "../auth/support-view.ts";

export { supportOf } from "../auth/support-view.ts";

export type { Impersonator } from "../auth/impersonation.ts";

export type { MembershipClaim } from "../auth/entitlements.ts";

export type { LiveCountSeed } from "../realtime/live.ts";
