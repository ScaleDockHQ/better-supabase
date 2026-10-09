import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { EventSink } from "../../events/index.ts";
import type { JobHandler } from "../jobs/queue.ts";

import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok, type Result } from "../../core/result.ts";
import { fromStorageError } from "../../storage/errors.ts";
import { toCsv } from "../csv.ts";
import {
  blockCall,
  errorText,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  stringsOf,
  textOf,
  toInstant,
  type BlockTemporalOptions,
  applyTemporal,
} from "../shared.ts";

interface StorageReply<T> {
  readonly data: T | null;
  readonly error: unknown;
}

/** An entry of `storage.from(bucket).list(prefix)`; folders have no `id`. */
export interface StorageEntry {
  readonly name: string;
  readonly id: string | null;
}

/** The `supabase.storage.from(bucket)` methods the lifecycle blocks use. */
export interface LifecycleBucket {
  upload(
    path: string,
    body: Blob,
    options?: { contentType?: string; upsert?: boolean },
  ): PromiseLike<StorageReply<unknown>>;
  createSignedUrl(
    path: string,
    expiresIn: number,
    options?: { download?: string | boolean },
  ): PromiseLike<StorageReply<{ readonly signedUrl: string }>>;
  list(
    path?: string,
    options?: { limit?: number; offset?: number },
  ): PromiseLike<StorageReply<readonly StorageEntry[]>>;
  remove(paths: string[]): PromiseLike<StorageReply<unknown>>;
}

/** `supabase.storage`, typed structurally. */
export interface LifecycleStorage {
  from(bucket: string): LifecycleBucket;
}

export type DataExportStatus = "pending" | "running" | "ready" | "failed";

export interface DataExport {
  readonly id: string;
  readonly subject: "user" | "organization";
  readonly userId: string | undefined;
  readonly organizationId: string | undefined;
  readonly status: DataExportStatus;
  readonly bucket: string;
  /** Object paths, one file per table: `{id}/{schema.table}.ndjson` (or `.csv`). */
  readonly files: readonly string[];
  readonly error: string | undefined;
  readonly requestedBy: string | undefined;
  readonly requestedAt: Temporal.Instant;
  readonly completedAt: Temporal.Instant | undefined;
  /** After this the files are no longer served. */
  readonly expiresAt: Temporal.Instant | undefined;
}

export interface OrganizationDeletion {
  readonly organizationId: string;
  readonly requestedBy: string | undefined;
  readonly requestedAt: Temporal.Instant;
  readonly purgeAfter: Temporal.Instant;
  readonly cancelledAt: Temporal.Instant | undefined;
  readonly purgedAt: Temporal.Instant | undefined;
}

export interface DataExportDownload {
  readonly export: DataExport;
  /** One signed URL per file, keyed by the table it holds. */
  readonly files: readonly { readonly table: string; readonly url: string }[];
}

export interface DataLifecycleOptions extends BlockTemporalOptions {
  /** The caller's transport (`rpcTransport(supabase)`). */
  readonly transport: BlockTransport;
  /** The caller's `supabase.storage`, for `download`. */
  readonly storage?: LifecycleStorage;
  /** The module schema (`sql.modules.data-lifecycle.schema`), default `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /** Lifetime of a signed download URL in seconds. Default 300. */
  readonly downloadTtl?: number;
}

export interface DataLifecycle {
  /** Exports the caller's data, or a tenant's with `organizationId` (needs `organization.export`). */
  requestExport(options?: {
    readonly organizationId?: string;
  }): AsyncResult<DataExport>;
  /** The caller's exports, or a tenant's, newest first. */
  exports(organizationId?: string): AsyncResult<readonly DataExport[]>;
  /** Signed URLs for a ready export's files. */
  download(exportId: string): AsyncResult<DataExportDownload>;
  /**
   * Disables the tenant and schedules its purge after `grace` (an
   * interval such as `30 days` or a `Temporal.Duration`; default the
   * module's `grace` option). Needs `organization.delete`.
   */
  requestOrganizationDeletion(
    organizationId: string,
    options?: { readonly grace?: Temporal.Duration | string },
  ): AsyncResult<OrganizationDeletion>;
  /** The requester or an owner cancels; `undefined` when nothing is pending. */
  cancelOrganizationDeletion(
    organizationId: string,
  ): AsyncResult<OrganizationDeletion | undefined>;
  /** The pending deletion, for members of the organization. */
  organizationDeletion(
    organizationId: string,
  ): AsyncResult<OrganizationDeletion | undefined>;
}

const EXPORT_STATUSES: readonly DataExportStatus[] = [
  "pending",
  "running",
  "ready",
  "failed",
];

function exportOf(value: unknown): DataExport {
  const row = recordOf(value, "data_exports");
  const status = EXPORT_STATUSES.find(
    (candidate) => candidate === row["status"],
  );
  if (status === undefined) {
    throw new TypeError(
      `Unknown export status ${JSON.stringify(row["status"])}`,
    );
  }
  return {
    id: textOf(row["id"]),
    subject: row["subject"] === "organization" ? "organization" : "user",
    userId: optionalText(row["user_id"]),
    organizationId: optionalText(row["organization_id"]),
    status,
    bucket: textOf(row["bucket"]),
    files: stringsOf(row["files"]),
    error: optionalText(row["error"]),
    requestedBy: optionalText(row["requested_by"]),
    requestedAt: toInstant(textOf(row["requested_at"])),
    completedAt: optionalInstant(row["completed_at"]),
    expiresAt: optionalInstant(row["expires_at"]),
  };
}

function deletionOf(value: unknown): OrganizationDeletion {
  const row = recordOf(value, "organization_deletions");
  return {
    organizationId: textOf(row["organization_id"]),
    requestedBy: optionalText(row["requested_by"]),
    requestedAt: toInstant(textOf(row["requested_at"])),
    purgeAfter: toInstant(textOf(row["purge_after"])),
    cancelledAt: optionalInstant(row["cancelled_at"]),
    purgedAt: optionalInstant(row["purged_at"]),
  };
}

const optionalDeletion = (value: unknown): OrganizationDeletion | undefined =>
  isRecord(value) ? deletionOf(value) : undefined;

function stored<T>(
  reply: PromiseLike<StorageReply<T>>,
): AsyncResult<NonNullable<T>> {
  return AsyncResult.from(async () => {
    try {
      const { data, error } = await reply;
      if (error) return err(fromStorageError(error, "storage.objects"));
      if (data === null || data === undefined) {
        return err(dbError("network", "Storage returned no data"));
      }
      return ok(data);
    } catch (cause) {
      return err(fromStorageError(cause, "storage.objects"));
    }
  });
}

/** The table a file holds: `{id}/public.projects.ndjson` gives `public.projects`. */
const tableOf = (path: string): string =>
  path.slice(path.lastIndexOf("/") + 1).replace(/\.(ndjson|csv)$/, "");

/** Exports and organization deletion as the caller. */
export function createDataLifecycle(
  options: DataLifecycleOptions,
): DataLifecycle {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const ttl = options.downloadTtl ?? 300;
  return {
    requestExport: (request = {}) =>
      call(
        "request_data_export",
        request.organizationId === undefined
          ? { subject: "user" }
          : { subject: "organization", tenant: request.organizationId },
        exportOf,
      ),
    exports: (organizationId) =>
      call("list_data_exports", { tenant: organizationId }, (value) =>
        recordsOf(value, "list_data_exports").map(exportOf),
      ),
    download: (exportId) =>
      call("get_data_export", { id: exportId }, (value) => value).andThen(
        async (value) => {
          if (!isRecord(value)) {
            return err(
              dbError("not_found", "No export you can see has this id", {
                hint: "DATA_EXPORT_NOT_FOUND",
              }),
            );
          }
          const found = exportOf(value);
          if (found.status !== "ready") {
            return err(
              dbError("invalid_request", "The export is not ready", {
                hint: "DATA_EXPORT_NOT_READY",
              }),
            );
          }
          if (!options.storage) {
            return err(
              dbError(
                "invalid_request",
                "Pass storage to createDataLifecycle to download exports",
              ),
            );
          }
          const bucket = options.storage.from(found.bucket);
          const files: { table: string; url: string }[] = [];
          for (const path of found.files) {
            const signed = await stored(
              bucket.createSignedUrl(path, ttl, { download: true }),
            );
            if (!signed.ok) return signed;
            files.push({ table: tableOf(path), url: signed.data.signedUrl });
          }
          return ok({ export: found, files });
        },
      ),
    requestOrganizationDeletion: (organizationId, request = {}) =>
      call(
        "request_organization_deletion",
        {
          tenant: organizationId,
          grace:
            request.grace === undefined ? undefined : String(request.grace),
        },
        deletionOf,
      ),
    cancelOrganizationDeletion: (organizationId) =>
      call(
        "cancel_organization_deletion",
        { tenant: organizationId },
        optionalDeletion,
      ),
    organizationDeletion: (organizationId) =>
      call(
        "organization_deletion",
        { tenant: organizationId },
        optionalDeletion,
      ),
  };
}

export interface DataExporterOptions extends BlockTemporalOptions {
  /** A service-role transport: the export functions are granted to `service_role` only. */
  readonly transport: BlockTransport;
  /** A service-role `supabase.storage`, to write the files. */
  readonly storage: LifecycleStorage;
  readonly schema?: string;
  /** Rows read per call. Default 1000. */
  readonly pageSize?: number;
  /** The outbox `typePrefix`. Default `dev.better-supabase`. */
  readonly typePrefix?: string;
  /**
   * `ndjson` (default) writes one JSON object per line; `csv` writes RFC
   * 4180 CSV with a header row, nested values as JSON and formula-looking
   * text prefixed with `'`, for people who open exports in a spreadsheet.
   */
  readonly format?: "ndjson" | "csv";
  readonly concurrency?: number;
}

/** The payload `job` expects. */
export interface DataExportJob {
  readonly exportId: string;
}

export interface DataExporter {
  /**
   * Writes one NDJSON file per table, then marks the export ready (which
   * emits `data_export.completed`). A failure marks it failed and returns the error.
   */
  run(exportId: string, signal?: AbortSignal): AsyncResult<DataExport>;
  /** A jobs handler: `queue.work('data-exports', exporter.job)`. */
  readonly job: JobHandler<DataExportJob>;
  /** An outbox sink that runs each `data_export.requested` export. */
  sink(): EventSink;
}

/** Runs requested exports with a service-role client. */
export function createDataExporter(options: DataExporterOptions): DataExporter {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema);
  const pageSize = options.pageSize ?? 1000;
  const concurrency = options.concurrency ?? 4;
  if (!Number.isInteger(concurrency) || concurrency < 1) {
    throw new TypeError(
      "createDataExporter: concurrency must be a whole number above zero",
    );
  }
  const prefix = `${options.typePrefix ?? "dev.better-supabase"}.`;

  const write = async (
    claimed: DataExport,
    tables: readonly string[],
    signal: AbortSignal | undefined,
  ): Promise<Result<readonly string[]>> => {
    const bucket = options.storage.from(claimed.bucket);
    const csv = options.format === "csv";
    const exportTable = async (table: string): Promise<Result<string>> => {
      const lines: string[] = [];
      const records: Record<string, unknown>[] = [];
      let after: string | undefined;
      do {
        signal?.throwIfAborted();
        const page = await call(
          "data_export_rows",
          { id: claimed.id, table_name: table, after, page_size: pageSize },
          (value) => recordOf(value, "data_export_rows"),
        );
        if (!page.ok) return page;
        const rows = Array.isArray(page.data["rows"]) ? page.data["rows"] : [];
        for (const row of rows) {
          if (csv) records.push(isRecord(row) ? row : { value: row });
          else lines.push(JSON.stringify(row));
        }
        after = optionalText(page.data["after"]);
      } while (after !== undefined);
      const path = `${claimed.id}/${table}.${csv ? "csv" : "ndjson"}`;
      const contentType = csv ? "text/csv" : "application/x-ndjson";
      const body = new Blob(
        csv
          ? records.length === 0
            ? []
            : [toCsv(records)]
          : lines.length === 0
            ? []
            : [`${lines.join("\n")}\n`],
        { type: contentType },
      );
      const uploaded = await stored(
        bucket.upload(path, body, { contentType, upsert: true }),
      );
      return uploaded.ok ? ok(path) : uploaded;
    };
    const files: string[] = [];
    let failed: Result<readonly string[]> | undefined;
    let next = 0;
    let stopped = false;
    const worker = async (): Promise<void> => {
      while (!stopped && failed === undefined && next < tables.length) {
        const index = next;
        next += 1;
        let written: Result<string>;
        try {
          written = await exportTable(tables[index]!);
        } catch (cause) {
          stopped = true;
          throw cause;
        }
        if (!written.ok) {
          failed ??= written;
          return;
        }
        files[index] = written.data;
      }
    };
    await Promise.all(
      Array.from({ length: Math.min(concurrency, tables.length) }, worker),
    );
    return failed ?? ok(files);
  };

  const run = (
    exportId: string,
    signal?: AbortSignal,
  ): AsyncResult<DataExport> =>
    call("claim_data_export", { id: exportId }, (value) => value).andThen(
      async (value): Promise<Result<DataExport>> => {
        if (!isRecord(value)) {
          return err(
            dbError("not_found", "No pending export has this id", {
              hint: "DATA_EXPORT_NOT_FOUND",
            }),
          );
        }
        const claimed = exportOf(value);
        let written: Result<readonly string[]>;
        try {
          written = await write(claimed, stringsOf(value["tables"]), signal);
        } catch (cause) {
          written = err(
            dbError(signal?.aborted ? "aborted" : "raised", errorText(cause), {
              hint: "DATA_EXPORT_FAILED",
            }),
          );
        }
        if (!written.ok) {
          await call(
            "fail_data_export",
            { id: claimed.id, error: written.error.message },
            () => undefined,
          );
          return written;
        }
        return call(
          "complete_data_export",
          { id: claimed.id, files: written.data },
          exportOf,
        );
      },
    );

  return {
    run,
    job: async (payload, _job, signal) => {
      await run(payload.exportId, signal).orThrow();
    },
    sink: () => ({
      async send(events) {
        for (const event of events) {
          const type = event.type.startsWith(prefix)
            ? event.type.slice(prefix.length)
            : event.type;
          if (type !== "data_export.requested" || !isRecord(event.data)) {
            continue;
          }
          const id = optionalText(event.data["exportId"]);
          if (id !== undefined) await run(id).orThrow();
        }
      },
    }),
  };
}

export interface OrganizationPurgerOptions extends BlockTemporalOptions {
  /** A service-role transport: `purge_organization()` is granted to `service_role` only. */
  readonly transport: BlockTransport;
  /** A service-role `supabase.storage`, to remove each bucket's organization prefix. */
  readonly storage?: LifecycleStorage;
  /**
   * Buckets to clear: a name, for a bucket whose paths start with the
   * organization id (`attachments`), or `{ bucket, path }` with a path
   * template such as `orgs/{organizationId}/files`, or a function that
   * returns the prefixes, for buckets laid out another way.
   */
  readonly buckets?: readonly PurgeBucket[];
  /** `createBilling(...)`, to cancel the subscription first. */
  readonly billing?: {
    cancelSubscription(organizationId: string): AsyncResult<unknown>;
  };
  /**
   * Also run the `sql.modules.data-lifecycle.options.anonymize` rules in
   * `job`, after the due purges. Default false.
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

export interface OrganizationPurge {
  readonly organizationId: string;
  /** Rows deleted per table. */
  readonly deleted: Readonly<Record<string, number>>;
  /** Objects removed per bucket. */
  readonly removed: Readonly<Record<string, number>>;
}

export interface OrganizationPurger {
  /** Cancels billing, removes the Storage prefixes, then deletes the rows. */
  purge(organizationId: string): AsyncResult<OrganizationPurge>;
  /** Purges every deletion past its grace period, oldest first; stops at the first error. */
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
   * Applies the `options.anonymize` rules to the rows whose time is up, at
   * most `limit` (1000) per rule; returns the rows anonymized per table.
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
      if (!page.ok) return page;
      for (const entry of page.data) {
        const path = `${folder}/${entry.name}`;
        if (entry.id === null) folders.push(path);
        else files.push(path);
      }
      if (page.data.length < REMOVE_BATCH) break;
    }
  }
  for (let start = 0; start < files.length; start += REMOVE_BATCH) {
    const removed = await stored(
      bucket.remove(files.slice(start, start + REMOVE_BATCH)),
    );
    if (!removed.ok) return removed;
  }
  return ok(files.length);
}

/** Purges organizations whose deletion grace period is over. */
export function createOrganizationPurger(
  options: OrganizationPurgerOptions,
): OrganizationPurger {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema);
  const purge = (organizationId: string): AsyncResult<OrganizationPurge> =>
    AsyncResult.from(async (): Promise<Result<OrganizationPurge>> => {
      if (options.billing) {
        const cancelled =
          await options.billing.cancelSubscription(organizationId);
        if (!cancelled.ok) return cancelled;
      }
      const removed: Record<string, number> = {};
      for (const entry of options.buckets ?? []) {
        if (!options.storage) {
          return err(
            dbError("invalid_request", "Pass storage to clear buckets"),
          );
        }
        const target = bucketPrefixes(entry, organizationId);
        if (!target.ok) return target;
        const { bucket, prefixes } = target.data;
        for (const prefix of prefixes) {
          const count = await removePrefix(
            options.storage.from(bucket),
            prefix,
          );
          if (!count.ok) return count;
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
        if (!result.ok) return result;
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
      if (exports.length === 0) return ok(0);
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
          if (!removed.ok) return removed;
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
      if (options.anonymize) await anonymizeDue().orThrow();
    },
  };
}
