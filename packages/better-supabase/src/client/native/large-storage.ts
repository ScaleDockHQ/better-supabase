import type { KeyValueStoreLike } from "./key-value.ts";
import type {
  AuthStorage,
  SecureStoreLike,
  SecureStoreOptionsLike,
} from "./storage.ts";

import { fromBase64, toBase64 } from "../../core/base64.ts";
import { keyValue } from "./key-value.ts";
import { safeKey } from "./storage.ts";

/** WebCrypto with AES-GCM: the global `crypto`, or `react-native-quick-crypto`. */
export interface AesCryptoLike {
  getRandomValues<T extends Uint8Array<ArrayBuffer>>(array: T): T;
  readonly subtle: Pick<SubtleCrypto, "importKey" | "encrypt" | "decrypt">;
}

export interface LargeSecureStorageOptions {
  /** Holds the 256-bit key per session key: `expo-secure-store`. */
  readonly secureStore: SecureStoreLike;
  /** Holds the encrypted session: MMKV or AsyncStorage. */
  readonly storage: KeyValueStoreLike;
  /** Defaults to the global `crypto`; Hermes needs `react-native-quick-crypto`. */
  readonly crypto?: AesCryptoLike;
  /** Passed to every `expo-secure-store` call. */
  readonly storeOptions?: SecureStoreOptionsLike;
}

const VERSION = "v1";
const IV_BYTES = 12;

function globalCrypto(): AesCryptoLike | undefined {
  // SAFETY: lib.dom types `crypto` as always present; Hermes may lack it.
  const { crypto } = globalThis as { readonly crypto?: Partial<AesCryptoLike> };
  // SAFETY: both members the storage calls are present.
  return crypto?.subtle && crypto.getRandomValues
    ? (crypto as AesCryptoLike)
    : undefined;
}

/**
 * Supabase Auth storage for sessions of any size: the session is encrypted
 * with AES-GCM and kept in MMKV or AsyncStorage, and only its key lives in
 * the keychain. A key that no longer decrypts (the app was reinstalled and
 * one store kept its data) reads as signed out and is replaced on the next
 * sign-in.
 *
 * ```ts
 * import * as SecureStore from 'expo-secure-store';
 * import AsyncStorage from '@react-native-async-storage/async-storage';
 * createClient(url, key, { auth: { storage: largeSecureStorage({ secureStore: SecureStore, storage: AsyncStorage }) } });
 * ```
 */
export function largeSecureStorage(
  options: LargeSecureStorageOptions,
): AuthStorage {
  const store = keyValue(options.storage);
  const secure = options.secureStore;
  const extra = options.storeOptions;
  const keyName = (key: string) => `${safeKey(key)}.aes`;
  const getSecret = (key: string) =>
    extra
      ? secure.getItemAsync(keyName(key), extra)
      : secure.getItemAsync(keyName(key));
  const setSecret = (key: string, value: string) =>
    extra
      ? secure.setItemAsync(keyName(key), value, extra)
      : secure.setItemAsync(keyName(key), value);
  const removeSecret = (key: string) =>
    extra
      ? secure.deleteItemAsync(keyName(key), extra)
      : secure.deleteItemAsync(keyName(key));

  const cryptoOf = (): AesCryptoLike => {
    const found = options.crypto ?? globalCrypto();
    if (!found)
      throw new Error(
        "better-supabase: largeSecureStorage needs WebCrypto; pass { crypto } from react-native-quick-crypto",
      );
    return found;
  };
  const importKey = (raw: Uint8Array<ArrayBuffer>) =>
    cryptoOf().subtle.importKey("raw", raw, "AES-GCM", false, [
      "encrypt",
      "decrypt",
    ]);

  return {
    async getItem(key) {
      const [secret, sealed] = await Promise.all([
        getSecret(key),
        store.get(key),
      ]);
      if (secret === null || sealed === null) return null;
      const [version, iv, data] = sealed.split(".");
      if (version !== VERSION || iv === undefined || data === undefined)
        return null;
      try {
        const plain = await cryptoOf().subtle.decrypt(
          { name: "AES-GCM", iv: fromBase64(iv) },
          await importKey(fromBase64(secret)),
          fromBase64(data),
        );
        return new TextDecoder().decode(plain);
      } catch {
        // The key and the data come from different installs.
        return null;
      }
    },
    async setItem(key, value) {
      const crypto = cryptoOf();
      const raw = crypto.getRandomValues(new Uint8Array(32));
      const iv = crypto.getRandomValues(new Uint8Array(IV_BYTES));
      const sealed = await crypto.subtle.encrypt(
        { name: "AES-GCM", iv },
        await importKey(raw),
        new TextEncoder().encode(value),
      );
      await setSecret(key, toBase64(raw));
      await store.set(
        key,
        `${VERSION}.${toBase64(iv)}.${toBase64(new Uint8Array(sealed))}`,
      );
    },
    async removeItem(key) {
      await Promise.all([store.remove(key), removeSecret(key)]);
    },
  };
}
