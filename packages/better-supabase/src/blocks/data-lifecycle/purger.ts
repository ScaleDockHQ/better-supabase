import type { BlockTransport } from "../../core/block-transport.ts";
import type { Result } from "../../core/result.ts";
import type {
  CredentialProvider,
  CredentialRef,
  CredentialSubject,
} from "../../credentials/provider.ts";
import type { JobHandler } from "../queue/types.ts";
import type { BlockTemporalOptions } from "../shared.ts";
import type { LifecycleBucket, LifecycleStorage } from "./data-lifecycle.ts";

import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { credentialRefInTenant } from "../../credentials/provider.ts";
import {
  applyTemporal,
  blockCall,
  isRecord,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";
import { deletionOf, stored } from "./data-lifecycle.ts";

export interface OrganizationPurgerOptions extends BlockTemporalOptions {
  /**
   * A service-role transport: `purge_organization()` is granted to
   * `service_role` only.
   */
  readonly transport: BlockTransport;
  /**
   * A service-role `supabase.storage`, to remove each bucket's organization
   * prefix.
   */
  readonly storage?: LifecycleStorage;
  /**
   * Buckets to clear: a name, for a bucket whose paths start with the
   * organization id (`attachments`), or `{ bucket, path }` with a path template
   * such as `orgs/{organizationId}/files`, or a function that returns the
   * prefixes, for buckets laid out another way.
   */
  readonly buckets?: readonly PurgeBucket[];
  /** `createBilling(...)`, to cancel the subscription first. */
  readonly billing?: {
    cancelSubscription(organizationId: string): AsyncResult<unknown>;
  };
  /**
   * Revokes the `credential_ref`s in the rows the purge deletes (provider keys,
   * connector servers and grants, workflow credentials) before it deletes them.
   * Only refs that carry the organization as their `tenant` are revoked; the
   * rest are returned in `credentials.unrevoked`.
   */
  readonly credentials?: CredentialProvider;
  /**
   * Also run the `blocks.data-lifecycle.options.anonymize` rules in `job`,
   * after the due purges. Default false.
   */
  readonly anonymize?: boolean;
  readonly schema?: string;
}

/** A bucket the purger clears, and where the organization's objects are. */
export type PurgeBucket =
  | string
  | {
      readonly bucket: string;
      /** A prefix template with `{organizationId}`, or the prefixes for an id. */
      readonly path:
        | string
        | ((organizationId: string) => string | readonly string[]);
    };

/** The prefixes an entry of `buckets` clears for an organization. */
function bucketPrefixes(
  entry: PurgeBucket,
  organizationId: string,
): Result<{ readonly bucket: string; readonly prefixes: readonly string[] }> {
  if (typeof entry === "string") {
    return ok({ bucket: entry, prefixes: [organizationId] });
  }

  const paths =
    typeof entry.path === "function"
      ? entry.path(organizationId)
      : entry.path.replaceAll("{organizationId}", organizationId);

  const prefixes = (typeof paths === "string" ? [paths] : [...paths]).map(
    (path) => path.replace(/\/+$/, ""),
  );

  const unsafe = prefixes.find((prefix) => !prefix.includes(organizationId));

  if (unsafe !== undefined) {
    return err(
      dbError(
        "invalid_request",
        `buckets.${entry.bucket}: the prefix "${unsafe}" doesn't contain the organization id, so it could clear other tenants' objects`,
      ),
    );
  }

  return ok({ bucket: entry.bucket, prefixes });
}

/** A `credential_ref` the purge deleted without revoking it. */
export interface UnrevokedCredential {
  /** `schema.table`. */
  readonly table: string;
  readonly column: string;
  readonly ref: CredentialRef;
  readonly subject: CredentialSubject;
  /**
   * `foreign`: the ref doesn't carry the organization as its tenant, so it may
   * name a credential that someone else still uses; `no_provider`: the purger
   * has no `credentials`; `not_revocable`: the provider can't revoke it.
   */
  readonly reason: "foreign" | "no_provider" | "not_revocable";
}

export interface OrganizationPurge {
  readonly organizationId: string;
  /** Rows deleted per table. */
  readonly deleted: Readonly<Record<string, number>>;
  /** Objects removed per bucket. */
  readonly removed: Readonly<Record<string, number>>;
  readonly credentials: {
    /** Refs revoked through `credentials`. */
    readonly revoked: number;
    /** Refs in the purged rows the provider still holds, for the app to handle. */
    readonly unrevoked: readonly UnrevokedCredential[];
  };
}

export interface OrganizationPurger {
  /**
   * Checks that the deletion is due, cancels billing, revokes the
   * organization's credentials, removes the Storage prefixes, then deletes the
   * rows.
   */
  purge(organizationId: string): AsyncResult<OrganizationPurge>;
  /**
   * Purges every deletion past its grace period, oldest first; stops at the
   * first error.
   */
  purgeDue(options?: {
    readonly limit?: number;
  }): AsyncResult<readonly OrganizationPurge[]>;
  /** A jobs handler for a cron queue: purges what is due. */
  readonly job: JobHandler<{ readonly limit?: number }>;
  /**
   * Removes the files of exports past their `expiresAt` from Storage, then
   * their rows; returns how many exports it removed. Needs `storage`.
   */
  purgeExports(options?: { readonly limit?: number }): AsyncResult<number>;
  /**
   * Applies the `options.anonymize` rules to the rows whose time is up, at most
   * `limit` (1000) per rule; returns the rows anonymized per table.
   */
  anonymizeDue(options?: {
    readonly limit?: number;
  }): AsyncResult<Readonly<Record<string, number>>>;
}

const REMOVE_BATCH = 1000;

async function removePrefix(
  bucket: LifecycleBucket,
  prefix: string,
): Promise<Result<number>> {
  const files: string[] = [];
  const folders = [prefix];

  while (folders.length > 0) {
    const folder = folders.pop() ?? prefix;

    for (let offset = 0; ; offset += REMOVE_BATCH) {
      const page = await stored(
        bucket.list(folder, { limit: REMOVE_BATCH, offset }),
      );

      if (!page.ok) {
        return page;
      }

      for (const entry of page.data) {
        const path = `${folder}/${entry.name}`;

        if (entry.id === null) {
          folders.push(path);
        } else {
          files.push(path);
        }
      }

      if (page.data.length < REMOVE_BATCH) {
        break;
      }
    }
  }

  for (let start = 0; start < files.length; start += REMOVE_BATCH) {
    const removed = await stored(
      bucket.remove(files.slice(start, start + REMOVE_BATCH)),
    );

    if (!removed.ok) {
      return removed;
    }
  }

  return ok(files.length);
}

interface PurgeCredentialRow {
  readonly table: string;
  readonly column: string;
  readonly ref: CredentialRef;
  readonly subject: CredentialSubject;
  readonly inTenant: boolean;
}

function purgeCredentialOf(value: unknown): PurgeCredentialRow | undefined {
  if (!isRecord(value)) {
    return undefined;
  }

  const ref = value["ref"];

  if (!isRecord(ref) || typeof ref["provider"] !== "string") {
    return undefined;
  }

  const userId = optionalText(value["user_id"]);

  return {
    table: textOf(value["table"]),
    column: textOf(value["column"]),
    // SAFETY: an object with a string provider, the CredentialRef shape.
    ref: ref as CredentialRef,
    subject:
      userId === undefined ? { type: "app" } : { type: "user", id: userId },
    inTenant: value["in_tenant"] === true,
  };
}

/** Purges organizations whose deletion grace period is over. */
export function createOrganizationPurger(
  options: OrganizationPurgerOptions,
): OrganizationPurger {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema);

  const revokeCredentials = (
    organizationId: string,
    rows: readonly PurgeCredentialRow[],
  ): AsyncResult<OrganizationPurge["credentials"]> =>
    AsyncResult.from(async () => {
      let revoked = 0;
      const unrevoked: UnrevokedCredential[] = [];

      const keep = (
        row: PurgeCredentialRow,
        reason: UnrevokedCredential["reason"],
      ): void => {
        unrevoked.push({
          table: row.table,
          column: row.column,
          ref: row.ref,
          subject: row.subject,
          reason,
        });
      };

      for (const row of rows) {
        if (!row.inTenant || !credentialRefInTenant(row.ref, organizationId)) {
          keep(row, "foreign");
        } else if (options.credentials === undefined) {
          keep(row, "no_provider");
        } else if (options.credentials.capabilities(row.ref).revoke) {
          const result = await options.credentials.revoke(row.ref, {
            subject: row.subject,
          });

          if (!result.ok) {
            return result;
          }

          revoked += 1;
        } else {
          keep(row, "not_revocable");
        }
      }

      return ok({ revoked, unrevoked });
    });

  const purge = (organizationId: string): AsyncResult<OrganizationPurge> =>
    AsyncResult.from(async (): Promise<Result<OrganizationPurge>> => {
      const refs = await call(
        "organization_credential_refs",
        { tenant: organizationId },
        (value) =>
          Array.isArray(value)
            ? value.flatMap((row) => {
                const parsed = purgeCredentialOf(row);

                return parsed ? [parsed] : [];
              })
            : [],
      );

      if (!refs.ok) {
        return refs;
      }

      if (options.billing) {
        const cancelled =
          await options.billing.cancelSubscription(organizationId);

        if (!cancelled.ok) {
          return cancelled;
        }
      }

      const credentials = await revokeCredentials(organizationId, refs.data);

      if (!credentials.ok) {
        return credentials;
      }

      const removed: Record<string, number> = {};

      for (const entry of options.buckets ?? []) {
        if (!options.storage) {
          return err(
            dbError("invalid_request", "Pass storage to clear buckets"),
          );
        }

        const target = bucketPrefixes(entry, organizationId);

        if (!target.ok) {
          return target;
        }

        const { bucket, prefixes } = target.data;

        for (const prefix of prefixes) {
          const count = await removePrefix(
            options.storage.from(bucket),
            prefix,
          );

          if (!count.ok) {
            return count;
          }

          removed[bucket] = (removed[bucket] ?? 0) + count.data;
        }
      }

      return call("purge_organization", { tenant: organizationId }, (value) => {
        const row = recordOf(value, "purge_organization");
        const deleted = isRecord(row["deleted"]) ? row["deleted"] : {};

        return {
          organizationId: textOf(row["organizationId"]),
          deleted: Object.fromEntries(
            Object.entries(deleted).map(([table, count]) => [
              table,
              Number(count),
            ]),
          ),
          removed,
          credentials: credentials.data,
        };
      });
    });

  const purgeDue = (
    due: { readonly limit?: number } = {},
  ): AsyncResult<readonly OrganizationPurge[]> =>
    call("due_organization_deletions", { max_rows: due.limit }, (value) =>
      recordsOf(value, "due_organization_deletions").map(deletionOf),
    ).andThen(async (deletions) => {
      const purged: OrganizationPurge[] = [];

      for (const deletion of deletions) {
        const result = await purge(deletion.organizationId);

        if (!result.ok) {
          return result;
        }

        purged.push(result.data);
      }

      return ok(purged);
    });

  const purgeExports = (
    expired: { readonly limit?: number } = {},
  ): AsyncResult<number> =>
    call("expired_data_exports", { max_rows: expired.limit ?? 100 }, (value) =>
      recordsOf(value, "expired_data_exports").map((row) => ({
        id: textOf(row["id"]),
        bucket: textOf(row["bucket"]),
        files: Array.isArray(row["files"])
          ? row["files"].filter((file) => typeof file === "string")
          : [],
      })),
    ).andThen(async (exports) => {
      if (exports.length === 0) {
        return ok(0);
      }

      const storage = options.storage;

      if (!storage) {
        return err(
          dbError("invalid_request", "Pass storage to remove export files"),
        );
      }

      for (const entry of exports) {
        for (let start = 0; start < entry.files.length; start += REMOVE_BATCH) {
          const removed = await stored(
            storage
              .from(entry.bucket)
              .remove(entry.files.slice(start, start + REMOVE_BATCH)),
          );

          if (!removed.ok) {
            return removed;
          }
        }
      }

      return call(
        "forget_data_exports",
        { ids: exports.map((entry) => entry.id) },
        (value) => Number(value ?? 0),
      );
    });

  const anonymizeDue = (
    due: { readonly limit?: number } = {},
  ): AsyncResult<Readonly<Record<string, number>>> =>
    call("anonymize_due", { max_rows: due.limit }, (value) =>
      Object.fromEntries(
        Object.entries(isRecord(value) ? value : {}).map(([table, count]) => [
          table,
          Number(count),
        ]),
      ),
    );

  return {
    purgeExports,
    purge,
    purgeDue,
    anonymizeDue,
    job: async (payload) => {
      await purgeDue(payload).orThrow();

      if (options.anonymize) {
        await anonymizeDue().orThrow();
      }
    },
  };
}
