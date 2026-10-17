import type { SupabaseClient } from "@supabase/supabase-js";

import type { TopicPort } from "../realtime/watch-topic.ts";

import { AsyncResult, err, ok } from "../core/result.ts";
import { fromStorageError } from "../storage/errors.ts";

export type {
  TopicHandle,
  TopicPort,
  TopicWatch,
} from "../realtime/watch-topic.ts";

/**
 * A string store: `localStorage` on the web (`webStorage()`), AsyncStorage,
 * MMKV or SecureStore on React Native (`nativeStorage()`).
 */
export interface StoragePort {
  readonly get: (key: string) => Promise<string | null>;
  readonly set: (key: string, value: string) => Promise<void>;
  readonly remove: (key: string) => Promise<void>;
}

/** A key combination. `mod` is Cmd on macOS and Ctrl elsewhere. */
export interface Shortcut {
  readonly key: string;
  readonly mod?: boolean;
  readonly shift?: boolean;
  readonly alt?: boolean;
}

/** Runs `run` on each press of `shortcut` until the returned function is called. */
export type KeyboardPort = (shortcut: Shortcut, run: () => void) => () => void;

/** A file the user picked, readable on every platform. */
export interface PickedFile {
  readonly name: string;
  /** The MIME type, when the platform reports one. */
  readonly type: string | undefined;
  readonly size: number | undefined;
  /** The local URI on React Native; `undefined` on the web. */
  readonly uri: string | undefined;
  /** The bytes: a `Blob` on the web, an `ArrayBuffer` on React Native. */
  readonly read: () => Promise<Blob | ArrayBuffer>;
}

export interface PickFilesOptions {
  /** MIME types or extensions, such as `image/*` or `.pdf`. */
  readonly accept?: readonly string[];
  readonly multiple?: boolean;
}

/** Opens the platform's file picker; resolves with no files when the user cancels. */
export type FilePickerPort = (
  options?: PickFilesOptions,
) => Promise<readonly PickedFile[]>;

export interface UploadDestination {
  readonly bucket: string;
  readonly path: string;
  readonly upsert?: boolean;
}

/** Uploads a picked file and resolves with its stored path. */
export type UploadPort = (
  file: PickedFile,
  to: UploadDestination,
) => AsyncResult<{ readonly path: string }>;

/** The device's push token for the platform's push service. */
export interface PushTokenPort {
  /** The push provider the token belongs to, such as `expo` or `webpush`. */
  readonly provider: string;
  /**
   * The token, asking for permission first unless `request` is false.
   * Resolves with `null` when the user denies it or the platform has none.
   */
  readonly token: (options?: {
    readonly request?: boolean;
  }) => Promise<string | null>;
}

/** The URL the app opened with, and the ones it opens later. */
export interface DeepLinkPort {
  readonly initial: () => Promise<string | null>;
  readonly subscribe: (listener: (url: string) => void) => () => void;
}

/**
 * The platform services block controllers use. `createClient` from
 * `better-supabase/client` fills the web ports, and `nativePorts()` from
 * `better-supabase/client/native` the React Native ones.
 */
export interface ClientPorts {
  readonly topic?: TopicPort;
  readonly storage?: StoragePort;
  readonly keyboard?: KeyboardPort;
  readonly files?: FilePickerPort;
  readonly upload?: UploadPort;
  readonly push?: PushTokenPort;
  readonly links?: DeepLinkPort;
}

/** A storage port that keeps values in memory, for tests and server renders. */
export function memoryStorage(
  initial: Readonly<Record<string, string>> = {},
): StoragePort {
  const values = new Map(Object.entries(initial));
  return {
    get: (key) => Promise.resolve(values.get(key) ?? null),
    set: (key, value) => {
      values.set(key, value);
      return Promise.resolve();
    },
    remove: (key) => {
      values.delete(key);
      return Promise.resolve();
    },
  };
}

/** The upload port over Supabase Storage, for web and native picked files alike. */
export function storageUpload(
  supabase: Pick<SupabaseClient, "storage">,
): UploadPort {
  return (file, to) =>
    AsyncResult.from(async () => {
      try {
        const body = await file.read();
        const { data, error } = await supabase.storage
          .from(to.bucket)
          .upload(to.path, body, {
            ...(file.type === undefined ? {} : { contentType: file.type }),
            ...(to.upsert === undefined ? {} : { upsert: to.upsert }),
          });
        if (error) {
          return err(fromStorageError(error, to.bucket));
        }
        return ok({ path: data.path });
      } catch (cause) {
        return err(fromStorageError(cause, to.bucket));
      }
    });
}
