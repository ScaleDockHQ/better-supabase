import type { BootstrapPermissions } from "../../core/bootstrap-permissions.ts";

import { expandBootstrapPermissions } from "../../core/bootstrap-permissions.ts";

/** The part of MMKV (or any string store) the permissions snapshot uses. */
export interface PermissionStore {
  getString(key: string): string | undefined;
  set(key: string, value: string): void;
  delete(key: string): void;
}

const keyOf = (userId: string, tenant: string, authzVersion: number): string =>
  `bsb.permissions.${userId}.${tenant}.${String(authzVersion)}`;

/**
 * A compact bootstrap payload kept on device, keyed by user, tenant and
 * `authz_ver`. A different version misses, so a role change cannot reuse the
 * previous keys. Wire this to `SessionProvider`'s `onAuthzChange`.
 */
export function nativePermissions(store: PermissionStore): {
  read(
    userId: string,
    tenant: string,
    authzVersion: number,
  ): BootstrapPermissions | undefined;
  write(
    userId: string,
    tenant: string,
    authzVersion: number,
    wire: unknown,
  ): void;
  clear(userId: string, tenant: string, authzVersion: number): void;
} {
  return {
    read(userId, tenant, authzVersion) {
      const raw = store.getString(keyOf(userId, tenant, authzVersion));

      if (raw === undefined) {
        return;
      }

      try {
        return expandBootstrapPermissions(JSON.parse(raw));
      } catch {
        return;
      }
    },
    write(userId, tenant, authzVersion, wire) {
      store.set(keyOf(userId, tenant, authzVersion), JSON.stringify(wire));
    },
    clear(userId, tenant, authzVersion) {
      store.delete(keyOf(userId, tenant, authzVersion));
    },
  };
}
