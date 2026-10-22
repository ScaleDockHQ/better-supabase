import type { SupportView } from "../auth/support-view.ts";
import type { AuthSession } from "../auth/view.ts";
import type { QuerySpec } from "../core/spec.ts";
import type { LiveCountSeed } from "../realtime/live.ts";
import type {
  useBlockEvent as clientUseBlockEvent,
  useBlockMutation as clientUseBlockMutation,
  useBlockQuery as clientUseBlockQuery,
} from "./block-hooks.ts";
import type { useEntityForm as clientUseEntityForm } from "./entity-form.ts";
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
import type { usePresence as clientUsePresence } from "./presence.ts";
import type { useRecordListState as clientUseRecordListState } from "./record-list.ts";
import type { createRecordProvider as clientCreateRecordProvider } from "./record.ts";
import type { useDebouncedSearch as clientUseDebouncedSearch } from "./search.ts";
import type {
  useSignIn as clientUseSignIn,
  useSignOut as clientUseSignOut,
} from "./sign-in.ts";
import type {
  useImage as clientUseImage,
  useSignedUrl as clientUseSignedUrl,
  useUpload as clientUseUpload,
} from "./storage.ts";

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

export { fieldErrorsOf } from "../bindings/field-errors.ts";

export { escapeLike } from "../ir/escape-like.ts";

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

export type {
  RecordListQueryStates,
  RecordListState,
  RecordListUrl,
  RecordListUrlState,
} from "./record-list.ts";

export type { EntityFormState, UseEntityFormOptions } from "./entity-form.ts";

export type {
  RecordActionsOf,
  RecordContextValue,
  RecordInitial,
  RecordProviderKit,
  RecordProviderProps,
  RecordState,
  RecordWriteHandlers,
} from "./record.ts";

export type {
  AuthHookOptions,
  DebouncedSearch,
  DebouncedSearchOptions,
  PendingState,
  Presence,
  PresenceHookOptions,
  ImageSource,
  PresenceTopic,
  SignedUrl,
  SignedUrlSource,
  SignIn,
  SignOut,
  StorageImage,
  Upload,
  UploadStatus,
  UploadTarget,
  UseImageOptions,
  UseUploadOptions,
} from "./index.ts";

export type { AuthSession } from "../auth/view.ts";

export type { SupportView } from "../auth/support-view.ts";

export { supportOf } from "../auth/support-view.ts";

export type { Impersonator } from "../auth/impersonation.ts";

export type { MembershipClaim } from "../auth/entitlements.ts";

export type { LiveCountSeed } from "../realtime/live.ts";

function clientOnly(name: string): () => never {
  return () => {
    throw new Error(
      `better-supabase: ${name}() runs in Client Components only. In Server Components use \`bsb.context()\` or \`db.$run(spec)\`.`,
    );
  };
}

/** The `react-server` build of `useSession`: await `bsb.session()` instead. */
export const useSession: <C = unknown, P = unknown>() => AuthSession<C, P> =
  clientOnly("useSession");

/**
 * The `react-server` build of `useSupportSession`: use `supportOf(await
 * bsb.session())` instead.
 */
export const useSupportSession: () => SupportView | undefined =
  clientOnly("useSupportSession");

/**
 * The `react-server` build of `useLiveCount`: render the `bsb.liveCount()` seed
 * instead.
 */
export const useLiveCount: (
  source: QuerySpec<string, "count", number> | LiveCountSeed | null | undefined,
  options?: LiveCountHookOptions,
) => LiveCount = clientOnly("useLiveCount");

/**
 * The `react-server` build of `useAction`: call the Server Action directly
 * instead.
 */
export const useAction: <I, T>(
  action: (input: I) => Promise<ActionResultOf<T>>,
  options?: UseActionOptions<ActionInputOf<I>, T>,
) => ActionHandle<ActionInputOf<I>, T> = clientOnly("useAction");

/**
 * The `react-server` build of `useActionForm`: render the form in a Client
 * Component.
 */
export const useActionForm: <T>(
  action: (input: FormData) => Promise<ActionResultOf<T>>,
  options?: UseActionFormOptions<T>,
) => ActionForm<T> = clientOnly("useActionForm");

/**
 * The `react-server` build of `usePresence`: join presence in a Client
 * Component.
 */
export const usePresence: typeof clientUsePresence = clientOnly("usePresence");

/**
 * The `react-server` build of `useSignIn`: sign in from a Client Component or a
 * Server Action.
 */
export const useSignIn: typeof clientUseSignIn = clientOnly("useSignIn");

/**
 * The `react-server` build of `useSignOut`: sign out from a Client Component or
 * a Server Action.
 */
export const useSignOut: typeof clientUseSignOut = clientOnly("useSignOut");

/**
 * The `react-server` build of `useBlockQuery`: call the block method and await
 * it instead.
 */
export const useBlockQuery: typeof clientUseBlockQuery =
  clientOnly("useBlockQuery");

/**
 * The `react-server` build of `useBlockMutation`: call the block method from a
 * Server Action instead.
 */
export const useBlockMutation: typeof clientUseBlockMutation =
  clientOnly("useBlockMutation");

/** The `react-server` build of `useBlockEvent`: listen from a Client Component. */
export const useBlockEvent: typeof clientUseBlockEvent =
  clientOnly("useBlockEvent");

/**
 * The `react-server` build of `createRecordProvider`: call it in a `"use
 * client"` module, such as the generated `-provider.tsx`.
 */
export const createRecordProvider: typeof clientCreateRecordProvider =
  clientOnly("createRecordProvider");

/**
 * The `react-server` build of `useDebouncedSearch`: read the term from
 * `searchParams` instead.
 */
export const useDebouncedSearch: typeof clientUseDebouncedSearch =
  clientOnly("useDebouncedSearch");

/**
 * The `react-server` build of `useSignedUrl`: await `bucket.signedUrl()`
 * instead.
 */
export const useSignedUrl: typeof clientUseSignedUrl =
  clientOnly("useSignedUrl");

/** The `react-server` build of `useImage`: await `bucket.renderUrl()` instead. */
export const useImage: typeof clientUseImage = clientOnly("useImage");

/** The `react-server` build of `useUpload`: upload from a Client Component. */
export const useUpload: typeof clientUseUpload = clientOnly("useUpload");

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

/**
 * The `react-server` build of `useRecordListState`: parse the search params
 * with the list's `parse` instead.
 */
export const useRecordListState: typeof clientUseRecordListState =
  clientOnly("useRecordListState");

/**
 * The `react-server` build of `useEntityForm`: render the form in a client
 * component.
 */
export const useEntityForm: typeof clientUseEntityForm =
  clientOnly("useEntityForm");
