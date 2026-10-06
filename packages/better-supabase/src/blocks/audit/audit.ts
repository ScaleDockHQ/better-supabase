import type { BlockTransport } from "../../core/block-transport.ts";
import type { DbError, ErrorMapper } from "../../core/errors.ts";

import { rawError } from "../../core/block-transport.ts";
import { dbError, mapDbError } from "../../core/errors.ts";
import { AsyncResult, err, ok, toDbError } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";

// ---------------------------------------------------------------------------
// Audit log API (SQL module `audit`)

/** One audit entry as `list` returns it; fields the log doesn't have are absent. */
export interface AuditEntry {
  readonly id: string;
  readonly occurredAt: Temporal.Instant;
  readonly table?: string | null;
  readonly record?: string | null;
  readonly op?: string | null;
  readonly changed?: readonly string[] | null;
  readonly old?: Readonly<Record<string, unknown>> | null;
  readonly new?: Readonly<Record<string, unknown>> | null;
  readonly actorId?: string | null;
  readonly actorRole?: string | null;
  readonly actorKind?: string | null;
  readonly actorLabel?: string | null;
  readonly tenant?: string | null;
  readonly tenantLabel?: string | null;
  readonly impersonatedBy?: string | null;
  readonly impersonationReason?: string | null;
  readonly supportSession?: string | null;
  readonly eventType?: string | null;
  readonly category?: string | null;
  readonly outcome?: string | null;
  readonly source?: string | null;
  readonly targetType?: string | null;
  readonly targetLabel?: string | null;
  readonly summary?: string | null;
  readonly requestId?: string | null;
  readonly correlationId?: string | null;
  readonly scope?: string | null;
  readonly metadata?: Readonly<Record<string, unknown>> | null;
}

export interface AuditListOptions {
  readonly tenant?: string;
  readonly eventType?: string;
  readonly actorId?: string;
  readonly targetType?: string;
  readonly record?: string;
  readonly since?: Temporal.Instant;
  readonly until?: Temporal.Instant;
  /** Page: entries older than this one. Pass the last entry of the previous page. */
  readonly before?: Pick<AuditEntry, "id" | "occurredAt">;
  /** Up to 1000. Defaults to 50. */
  readonly limit?: number;
}

/** The restricted details `reveal` returns. */
export interface AuditDetails {
  readonly entry: string;
  readonly old?: Readonly<Record<string, unknown>> | null;
  readonly new?: Readonly<Record<string, unknown>> | null;
  readonly ip?: string | null;
  readonly userAgent?: string | null;
  readonly metadata?: Readonly<Record<string, unknown>> | null;
  readonly sessionId?: string | null;
  /** Per changed column: `{ old, new }`, values cut at 1000 characters. */
  readonly changes?: Readonly<
    Record<string, { readonly old: unknown; readonly new: unknown }>
  > | null;
}

/** The part of a Supabase Storage bucket `exportCsv` writes with. */
export interface AuditExportBucket {
  upload(
    path: string,
    body: Blob,
    options?: { readonly contentType?: string; readonly upsert?: boolean },
  ): PromiseLike<{ readonly error: unknown }>;
  createSignedUrl(
    path: string,
    expiresIn: number,
  ): PromiseLike<{
    readonly data: { readonly signedUrl: string } | null;
    readonly error: unknown;
  }>;
}

export interface AuditExportOptions extends Omit<
  AuditListOptions,
  "before" | "limit"
> {
  readonly tenant: string;
  /** `storage.from(bucket)`. */
  readonly bucket: AuditExportBucket;
  /** Defaults to `<tenant>/audit-<timestamp>.csv`. */
  readonly path?: string;
  /** Seconds the signed URL works. Defaults to 3600. */
  readonly expiresIn?: number;
  /** The most entries exported. Defaults to 100000. */
  readonly maxRows?: number;
  /** Columns, in order. Defaults to the common ones. */
  readonly columns?: readonly (keyof AuditEntry)[];
}

export interface AuditExport {
  readonly path: string;
  readonly signedUrl: string;
  readonly rows: number;
}

export interface AuditLogOptions {
  /** `sqlTransport(ctx.postgres)` for a member, `rpcTransport(supabase)`, or a service connection. */
  readonly transport: BlockTransport;
  /** The schema of the `audit` module. Defaults to `better_supabase`. */
  readonly schema?: string;
  readonly errorMappers?: readonly ErrorMapper[];
}

export interface AuditLog {
  /** A page of the entries the caller can read, newest first. */
  list(options?: AuditListOptions): AsyncResult<AuditEntry[]>;
  /**
   * One entry's restricted details (old and new records, per-column
   * changes, IP, user agent), recorded as `audit.revealed`. Needs the
   * restricted table and the `reveal` permission (the view permission by
   * default) in the entry's tenant.
   */
  reveal(entry: Pick<AuditEntry, "id"> | string): AsyncResult<AuditDetails>;
  /** A tenant's entries as CSV in Storage, with a signed URL to download it. */
  exportCsv(options: AuditExportOptions): AsyncResult<AuditExport>;
}

const DEFAULT_COLUMNS: readonly (keyof AuditEntry)[] = [
  "id",
  "occurredAt",
  "eventType",
  "category",
  "outcome",
  "actorId",
  "actorKind",
  "actorLabel",
  "targetType",
  "record",
  "targetLabel",
  "summary",
  "requestId",
];

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

function toEntry(row: Record<string, unknown>): AuditEntry {
  const occurredAt = row["occurredAt"];
  return {
    ...row,
    id: String(row["id"]),
    occurredAt:
      occurredAt instanceof Date
        ? temporal().Instant.fromEpochMilliseconds(occurredAt.getTime())
        : temporal().Instant.from(String(occurredAt)),
  };
}

/** A CSV field, quoted when it holds a separator, a quote or a line break. */
export function csvField(value: unknown): string {
  if (value === null || value === undefined) return "";
  const text =
    typeof value === "object" && !("toJSON" in value)
      ? JSON.stringify(value)
      : String(value);
  return /[",\r\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

/**
 * The `audit` SQL module as typed calls: a list query over the log (the
 * read policy decides what each caller sees), revealing restricted details
 * with a record of who looked, and CSV exports to Storage. For retention,
 * see `purgeAuditLog`.
 */
export function createAuditLog(options: AuditLogOptions): AuditLog {
  const schema = options.schema ?? "better_supabase";
  const mappers = options.errorMappers ?? [];
  const mapped = (cause: unknown): DbError => {
    const raw = rawError(cause);
    return raw ? mapDbError(raw, mappers) : toDbError(cause);
  };
  const call = (fn: string, args: Readonly<Record<string, unknown>>) =>
    options.transport.call(schema, fn, args);

  const page = async (listOptions: AuditListOptions): Promise<AuditEntry[]> => {
    const value = await call("list_audit_events", {
      for_tenant: listOptions.tenant ?? null,
      for_event_type: listOptions.eventType ?? null,
      for_actor: listOptions.actorId ?? null,
      for_target_type: listOptions.targetType ?? null,
      for_record: listOptions.record ?? null,
      since: listOptions.since?.toString() ?? null,
      until: listOptions.until?.toString() ?? null,
      before_at: listOptions.before?.occurredAt.toString() ?? null,
      before_id: listOptions.before?.id ?? null,
      max_items: listOptions.limit ?? 50,
    });
    return (Array.isArray(value) ? value : []).filter(isRecord).map(toEntry);
  };

  return {
    list: (listOptions = {}) =>
      AsyncResult.from(async () => {
        try {
          return ok(await page(listOptions));
        } catch (cause) {
          return err(mapped(cause));
        }
      }),
    reveal: (entry) =>
      AsyncResult.from(async () => {
        try {
          const value = await call("reveal_audit_entry", {
            entry: typeof entry === "string" ? entry : entry.id,
          });
          if (!isRecord(value)) {
            return err(dbError("not_found", "No such audit entry"));
          }
          return ok({ ...value, entry: String(value["entry"]) });
        } catch (cause) {
          return err(mapped(cause));
        }
      }),
    exportCsv: (exportOptions) =>
      AsyncResult.from(async () => {
        const columns = exportOptions.columns ?? DEFAULT_COLUMNS;
        const maxRows = exportOptions.maxRows ?? 100_000;
        const lines = [columns.join(",")];
        let rows = 0;
        let before: Pick<AuditEntry, "id" | "occurredAt"> | undefined;
        try {
          while (rows < maxRows) {
            const entries = await page({
              ...exportOptions,
              ...(before ? { before } : {}),
              limit: Math.min(1000, maxRows - rows),
            });
            for (const entry of entries)
              lines.push(columns.map((key) => csvField(entry[key])).join(","));
            rows += entries.length;
            if (entries.length < 1000) break;
            before = entries.at(-1);
          }
        } catch (cause) {
          return err(mapped(cause));
        }
        const path =
          exportOptions.path ??
          `${exportOptions.tenant}/audit-${temporal().Now.instant().epochMilliseconds}.csv`;
        const uploaded = await exportOptions.bucket.upload(
          path,
          new Blob([`${lines.join("\r\n")}\r\n`], { type: "text/csv" }),
          { contentType: "text/csv", upsert: false },
        );
        if (uploaded.error) return err(toDbError(uploaded.error));
        const signed = await exportOptions.bucket.createSignedUrl(
          path,
          exportOptions.expiresIn ?? 3600,
        );
        if (signed.error || !signed.data) {
          return err(toDbError(signed.error ?? new Error("No signed URL")));
        }
        return ok({ path, signedUrl: signed.data.signedUrl, rows });
      }),
  };
}
