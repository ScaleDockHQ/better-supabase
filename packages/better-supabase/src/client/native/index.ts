import type { SupabaseClient } from "@supabase/supabase-js";

import type { BetterSupabase } from "../../core/define.ts";
import type { DbExtraHelpers } from "../../core/repository-types.ts";
import type { AnyFunctions, AnyModels } from "../../schema/types.ts";
import type { BetterClient, BindClientOptions } from "../bind.ts";

import { provideConnectionRuntime } from "../../core/define-runtime-full.ts";
import { bindClient } from "../bind.ts";

provideConnectionRuntime();

/**
 * Like `createClient`, with the whole `db`: the offline engine batches reads
 * through `$many`, and apps read `$stats` and `$search` on the device.
 */
export function createNativeClient<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  B = unknown,
>(
  betterSupabase: BetterSupabase<M, D, F, E, C, P, B>,
  supabase: SupabaseClient,
  options: BindClientOptions = {},
): BetterClient<M, F, E, C, P, B, DbExtraHelpers<M>> {
  return bindClient<M, D, F, E, C, P, B, DbExtraHelpers<M>>(
    betterSupabase,
    supabase,
    options,
  );
}

export type {
  AuthSnapshot,
  AuthUser,
  BetterClient,
  BindClientOptions,
  ClientAuth,
} from "../bind.ts";

export {
  handleAuthDeepLink,
  linkParams,
  signInWithOAuthBrowser,
} from "./auth-link.ts";

export type {
  AuthLinkError,
  AuthLinkClient,
  AuthLinkResult,
  OAuthClient,
  OAuthSignInOptions,
  WebBrowserLike,
} from "./auth-link.ts";

export { AUTHZ_EVENT, authzUserTopic } from "../../core/authz-topic.ts";

export type { AuthzVersionSource } from "../../core/authz-topic.ts";

export { startNativeAuthzRefresh } from "./authz-refresh.ts";

export type {
  NativeAuthzRefreshClient,
  NativeAuthzRefreshOptions,
  PowerSyncReconnect,
} from "./authz-refresh.ts";

export { autoRefreshOnForeground } from "./auto-refresh.ts";

export type { AppStateLike, AutoRefreshClient } from "./auto-refresh.ts";

export { keyValue } from "./key-value.ts";

export {
  expoPushToken,
  nativeDeepLinks,
  nativeFilePicker,
  nativePorts,
  nativeStorage,
} from "./ports.ts";

export type {
  DocumentPickerAsset,
  DocumentPickerLike,
  ExpoNotificationsLike,
  ExpoPushTokenOptions,
  LinkingLike,
  NativePortsOptions,
} from "./ports.ts";

export { memoryStorage, storageUpload } from "../ports.ts";

export type {
  ClientPorts,
  DeepLinkPort,
  FilePickerPort,
  KeyboardPort,
  PickedFile,
  PickFilesOptions,
  PushTokenPort,
  Shortcut,
  StoragePort,
  TopicHandle,
  TopicPort,
  TopicWatch,
  UploadDestination,
  UploadPort,
} from "../ports.ts";

export type {
  AsyncStorageLike,
  KeyValue,
  KeyValueStoreLike,
  MmkvLike,
} from "./key-value.ts";

export { largeSecureStorage } from "./large-storage.ts";

export type {
  AesCryptoLike,
  LargeSecureStorageOptions,
} from "./large-storage.ts";

export { persistQueryCache } from "./persist.ts";

export type { PersistQueryCacheOptions, QueryPersister } from "./persist.ts";

export { syncQueryWithApp } from "./query.ts";

export type {
  FocusManagerLike,
  NetInfoLike,
  OnlineManagerLike,
  SyncQueryWithAppOptions,
} from "./query.ts";

export { secureStorage } from "./storage.ts";

export type {
  AuthStorage,
  SecureStorageOptions,
  SecureStoreOptionsLike,
  SecureStoreLike,
} from "./storage.ts";

export { contentTypeOf, uploadFromUri } from "./upload.ts";

export type { UploadFromUriOptions, UriUploadTarget } from "./upload.ts";
