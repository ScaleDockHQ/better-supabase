import type { DbError } from "../../core/errors.ts";
import type { Result } from "../../core/result.ts";
import type { AuthPort, Controller } from "../controller.ts";
import type { PermissionSet } from "./permissions-controller.ts";
import type { Permissions } from "./permissions.ts";

import { AsyncResult, ok } from "../../core/result.ts";
import { currentTenant } from "../../core/tenant-source.ts";
import { defineController, whileSignedIn } from "../controller.ts";

/**
 * What the permissions controller reads: `createPermissions()` or a batch of
 * it.
 */
export type PermissionSource<K extends string = string> = Pick<
  Permissions<K>,
  "permissions"
>;

interface Batch {
  readonly keys: Set<string>;
  readonly waiters: ((result: Result<PermissionSet>) => void)[];
}

/**
 * Joins the `permissions(keys)` calls made in the same tick for one tenant into
 * one `my_permissions` call, so every `<Can>` on a screen costs one round trip.
 * Each caller gets back only the keys it asked for.
 */
export function batchPermissions<K extends string>(
  source: PermissionSource<K>,
): PermissionSource<K> {
  const pending = new Map<string, Batch>();

  const flush = (tenant: string, batch: Batch): void => {
    pending.delete(tenant);
    // SAFETY: the batch holds only keys the callers passed as `K`.
    const keys = [...batch.keys] as K[];

    void source.permissions({ keys, tenant }).then((result) => {
      for (const waiter of batch.waiters) {
        waiter(result);
      }

      return result;
    });
  };

  return {
    permissions: ({ keys, ...options } = {}) => {
      const tenant = currentTenant(options.tenant);

      if (keys === undefined || tenant === undefined) {
        return source.permissions({ keys, ...options });
      }

      return AsyncResult.from(
        () =>
          new Promise((resolve) => {
            let batch = pending.get(tenant);

            if (batch === undefined) {
              const created: Batch = { keys: new Set(), waiters: [] };
              batch = created;
              pending.set(tenant, created);
              queueMicrotask(() => {
                flush(tenant, created);
              });
            }

            const wanted = new Set<string>(keys);

            for (const key of wanted) {
              batch.keys.add(key);
            }

            batch.waiters.push((result) => {
              resolve(
                result.ok
                  ? ok({
                      tenant,
                      keys: result.data.keys.filter((key) => wanted.has(key)),
                    })
                  : result,
              );
            });
          }),
      );
    },
  };
}

export interface PermissionsControllerOptions<K extends string = string> {
  /** `createPermissions()`, ideally through `batchPermissions`. */
  readonly client: PermissionSource<K>;
  readonly auth: AuthPort;
  /** The keys to check. */
  readonly keys: readonly K[];
  /**
   * The organization to check in. Without one every key reads false and nothing
   * loads.
   */
  readonly tenant: string | undefined;
}

export interface PermissionsSnapshot {
  /** `undefined` until the first load, and while signed out or without a tenant. */
  readonly permissions: PermissionSet | undefined;
  readonly error: DbError | undefined;
}

export interface PermissionsActions {
  /** Checks the keys again, such as after a role change the session missed. */
  readonly refresh: () => Promise<void>;
}

export type PermissionsController = Controller<
  PermissionsSnapshot,
  PermissionsActions
>;

/**
 * Which of `keys` the caller holds in `tenant`, for showing or hiding UI. It
 * loads again when another user signs in. UX only: RLS and the SQL functions
 * check every key again.
 */
export function createPermissionsController<K extends string>(
  options: PermissionsControllerOptions<K>,
): PermissionsController {
  const { client, keys, tenant } = options;

  return defineController<PermissionsSnapshot, PermissionsActions>(
    { permissions: undefined, error: undefined },
    (state) => {
      const refresh = async (): Promise<void> => {
        if (tenant === undefined) {
          return;
        }

        const run = state.run();
        const result = await client.permissions({ keys, tenant });

        if (run !== state.run()) {
          return;
        }

        state.set(
          result.ok
            ? { permissions: result.data, error: undefined }
            : { error: result.error },
        );
      };

      return {
        actions: { refresh },
        start: () => {
          if (tenant === undefined) {
            return;
          }

          return whileSignedIn(options.auth, () => {
            void refresh();

            return () => {
              state.set({ permissions: undefined });
            };
          });
        },
      };
    },
  );
}
