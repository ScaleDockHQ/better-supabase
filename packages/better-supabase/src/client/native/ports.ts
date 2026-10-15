import type { SupabaseClient } from "@supabase/supabase-js";

import type {
  ClientPorts,
  DeepLinkPort,
  FilePickerPort,
  StoragePort,
} from "../ports.ts";
import type { KeyValueStoreLike } from "./key-value.ts";
import type { ExpoNotificationsLike } from "./push-token.ts";

import { storageUpload } from "../ports.ts";
import { keyValue } from "./key-value.ts";
import { expoPushToken } from "./push-token.ts";

export { expoPushToken } from "./push-token.ts";
export type {
  ExpoNotificationsLike,
  ExpoPushTokenOptions,
} from "./push-token.ts";

/** The storage port over AsyncStorage, MMKV or any async string store. */
export function nativeStorage(store: KeyValueStoreLike): StoragePort {
  return keyValue(store);
}

/** The part of `expo-linking` (or React Native's `Linking`) the deep link port uses. */
export interface LinkingLike {
  getInitialURL(): Promise<string | null>;
  addEventListener(
    type: "url",
    listener: (event: { readonly url: string }) => void,
  ): { remove(): void };
}

/** The deep link port over `expo-linking`. */
export function nativeDeepLinks(linking: LinkingLike): DeepLinkPort {
  return {
    initial: () => linking.getInitialURL(),
    subscribe: (listener) => {
      const subscription = linking.addEventListener("url", ({ url }) => {
        listener(url);
      });
      return () => {
        subscription.remove();
      };
    },
  };
}

/** One asset of an `expo-document-picker` result. */
export interface DocumentPickerAsset {
  readonly uri: string;
  readonly name: string;
  readonly mimeType?: string | undefined;
  readonly size?: number | undefined;
}

/** The part of `expo-document-picker` the file picker port uses. */
export interface DocumentPickerLike {
  getDocumentAsync(options?: {
    readonly type?: string | string[];
    readonly multiple?: boolean;
    readonly copyToCacheDirectory?: boolean;
  }): Promise<
    | { readonly canceled: true; readonly assets: null }
    | {
        readonly canceled: false;
        readonly assets: readonly DocumentPickerAsset[];
      }
  >;
}

/**
 * The file picker port over `expo-document-picker`. Files are read through
 * `fetch`, which reads `file://` and `content://` URIs on React Native.
 */
export function nativeFilePicker(
  picker: DocumentPickerLike,
  read: (uri: string) => Promise<Response> = (uri) => fetch(uri),
): FilePickerPort {
  return async (options = {}) => {
    const picked = await picker.getDocumentAsync({
      ...(options.accept ? { type: [...options.accept] } : {}),
      multiple: options.multiple ?? false,
      copyToCacheDirectory: true,
    });
    if (picked.canceled) return [];
    return picked.assets.map((asset) => ({
      name: asset.name,
      type: asset.mimeType,
      size: asset.size,
      uri: asset.uri,
      read: async () => (await read(asset.uri)).arrayBuffer(),
    }));
  };
}

export interface NativePortsOptions {
  /** Uploads picked files to Supabase Storage. */
  readonly supabase?: Pick<SupabaseClient, "storage">;
  /** AsyncStorage or MMKV, for the storage port. */
  readonly storage?: KeyValueStoreLike;
  /** `expo-linking`, for the deep link port. */
  readonly linking?: LinkingLike;
  /** `expo-notifications`, for the push token port. */
  readonly notifications?: ExpoNotificationsLike;
  readonly projectId?: string | undefined;
  /** `expo-document-picker`, for the file picker port. */
  readonly documentPicker?: DocumentPickerLike;
}

/**
 * The React Native ports, from the Expo modules the app installs. Pass the
 * result to `createNativeClient(betterSupabase, supabase, { ports })`.
 *
 * ```ts
 * const ports = nativePorts({ supabase, storage: AsyncStorage, linking: Linking, notifications: Notifications });
 * ```
 */
export function nativePorts(options: NativePortsOptions): ClientPorts {
  return {
    ...(options.storage ? { storage: nativeStorage(options.storage) } : {}),
    ...(options.linking ? { links: nativeDeepLinks(options.linking) } : {}),
    ...(options.notifications
      ? {
          push: expoPushToken(options.notifications, {
            projectId: options.projectId,
          }),
        }
      : {}),
    ...(options.documentPicker
      ? { files: nativeFilePicker(options.documentPicker) }
      : {}),
    ...(options.supabase ? { upload: storageUpload(options.supabase) } : {}),
  };
}
