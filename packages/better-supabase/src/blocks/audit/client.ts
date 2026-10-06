import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { AuditEntry, OcsfProduct } from "./audit.ts";

import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import { toCsv } from "../csv.ts";
import {
  blockCall,
  instantArg,
  isRecord,
  optionalInstant,
  optionalText,
  stringsOf,
  textOf,
  type BlockTemporalOptions,
  applyTemporal,
} from "../shared.ts";
import { toOcsf } from "./audit.ts";

/**
 * One entry as `list_audit_events` returns it: the module's columns under
 * stable keys, whatever the adopted log calls them. Fields the log doesn't
 * have, or the caller may not read, are missing.
 */
export interface AuditRecord {
  readonly id: string;
  readonly occurredAt: Temporal.Instant;
  readonly op?: string;
  readonly table?: string;
  readonly record?: string;
  readonly changed?: readonly string[];
  readonly old?: Readonly<Record<string, unknown>>;
  readonly new?: Readonly<Record<string, unknown>>;
  readonly actorId?: string;
  readonly actorRole?: string;
  readonly actorKind?: string;
  readonly actorLabel?: string;
  readonly tenant?: string;
  readonly tenantLabel?: string;
  readonly impersonatedBy?: string;
  readonly impersonationReason?: string;
  readonly supportSession?: string;
  readonly eventType?: string;
  readonly category?: string;
  readonly outcome?: string;
  readonly source?: string;
  readonly targetType?: string;
  readonly targetLabel?: string;
  readonly summary?: string;
  readonly requestId?: string;
  readonly correlationId?: string;
  readonly scope?: string;
  readonly metadata?: Readonly<Record<string, unknown>>;
}

/** Where a page ends: pass it as `before` for the next, older page. */
export interface AuditCursor {
  readonly occurredAt: Temporal.Instant;
  readonly id: string;
}

export interface AuditListOptions {
  readonly organizationId?: string;
  readonly eventType?: string;
  readonly actorId?: string;
  readonly targetType?: string;
  readonly record?: string;
  /** Entries at or after this instant. */
  readonly since?: Temporal.Instant;
  /** Entries before this instant. */
  readonly until?: Temporal.Instant;
  /** `page.next` of the previous page; `undefined` starts at the newest. */
  readonly before?: AuditCursor | undefined;
  /** Default 50, at most 1000. */
  readonly limit?: number;
}

export interface AuditPage {
  readonly entries: readonly AuditRecord[];
  /** The cursor of the next page, or `undefined` on the last one. */
  readonly next: AuditCursor | undefined;
}

/** The restricted details `reveal` returns, when the entry has them. */
export interface AuditDetails {
  readonly entry: string;
  readonly old?: Readonly<Record<string, unknown>>;
  readonly new?: Readonly<Record<string, unknown>>;
  readonly ip?: string;
  readonly userAgent?: string;
  readonly metadata?: Readonly<Record<string, unknown>>;
  readonly sessionId?: string;
  readonly changes?: unknown;
}

export interface AuditExportOptions extends Omit<
  AuditListOptions,
  "before" | "limit"
> {
  /**
   * `ndjson` (default) writes the records as they are, `csv` a spreadsheet
   * with a header row, `ocsf` each record mapped with `toOcsf`.
   */
  readonly format?: "ndjson" | "csv" | "ocsf";
  /** Required for `ocsf`: `metadata.product`. */
  readonly product?: OcsfProduct;
  /** Entries per call. Default 500. */
  readonly batch?: number;
}

/** The part of `supabase.storage.from(bucket)` an export upload uses. */
export interface AuditExportBucket {
  upload(
    path: string,
    body: Blob,
    options?: { contentType?: string; upsert?: boolean },
  ): PromiseLike<{ readonly data: unknown; readonly error: unknown }>;
  createSignedUrl?(
    path: string,
    expiresIn: number,
    options?: { download?: string | boolean },
  ): PromiseLike<{
    readonly data: { readonly signedUrl: string } | null;
    readonly error: unknown;
  }>;
}

export interface AuditExportToStorageOptions extends AuditExportOptions {
  readonly storage: { from(bucket: string): AuditExportBucket };
  readonly bucket: string;
  /** The object path, such as `{organizationId}/audit/{jobId}.csv`. */
  readonly path: string;
  /** Also sign a download URL that lives this many seconds. */
  readonly signedUrlTtl?: number;
}

export interface AuditLogOptions extends BlockTemporalOptions {
  /** `sqlTransport(ctx.postgres)` for members, or `rpcTransport` over an API schema. */
  readonly transport: BlockTransport;
  /** The audit module's schema, or its API schema. Default `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

export interface AuditLog {
  /** A page of the entries the caller can read, newest first. */
  list(options?: AuditListOptions): AsyncResult<AuditPage>;
  /**
   * The restricted details of one entry for a caller with the reveal
   * permission in its tenant (or platform staff); the reveal is itself
   * recorded as `audit.revealed`. `not_found` otherwise.
   */
  reveal(entryId: string): AsyncResult<AuditDetails>;
  /** Every matching entry as NDJSON, CSV or OCSF, read page by page as the caller. */
  export(options?: AuditExportOptions): ReadableStream<Uint8Array>;
  /**
   * Writes an export to a Storage object, for a job that runs it in the
   * background (the data lifecycle export bucket, say), and returns the path
   * and a signed URL when `signedUrlTtl` is set.
   */
  exportToStorage(
    options: AuditExportToStorageOptions,
  ): AsyncResult<{ readonly path: string; readonly url: string | undefined }>;
}

const TEXT_KEYS = [
  "op",
  "table",
  "record",
  "actorId",
  "actorRole",
  "actorKind",
  "actorLabel",
  "tenant",
  "tenantLabel",
  "impersonatedBy",
  "impersonationReason",
  "supportSession",
  "eventType",
  "category",
  "outcome",
  "source",
  "targetType",
  "targetLabel",
  "summary",
  "requestId",
  "correlationId",
  "scope",
] as const;

function recordOfEntry(value: unknown): AuditRecord {
  const row = isRecord(value) ? value : {};
  const text: Partial<Record<(typeof TEXT_KEYS)[number], string>> = {};
  for (const key of TEXT_KEYS) {
    const found = optionalText(row[key]);
    if (found !== undefined) text[key] = found;
  }
  const json = (key: string) => {
    const found = row[key];
    return isRecord(found) ? found : undefined;
  };
  const old = json("old");
  const next = json("new");
  const metadata = json("metadata");
  return {
    id: textOf(row["id"]),
    occurredAt:
      optionalInstant(row["occurredAt"]) ??
      temporal().Instant.fromEpochMilliseconds(0),
    ...text,
    ...(Array.isArray(row["changed"])
      ? { changed: stringsOf(row["changed"]) }
      : {}),
    ...(old === undefined ? {} : { old }),
    ...(next === undefined ? {} : { new: next }),
    ...(metadata === undefined ? {} : { metadata }),
  };
}

/** The record in `exportAuditLog`'s `AuditEntry` shape, for `toOcsf`. */
function entryOf(record: AuditRecord): AuditEntry {
  return {
    id: record.id,
    occurredAt: record.occurredAt,
    op: record.op ?? "event",
    ...(record.table === undefined ? {} : { table: record.table }),
    ...(record.record === undefined ? {} : { record: record.record }),
    ...(record.changed === undefined ? {} : { changed: record.changed }),
    ...(record.actorId === undefined ? {} : { actor: record.actorId }),
    ...(record.actorRole === undefined ? {} : { actorRole: record.actorRole }),
    ...(record.tenant === undefined ? {} : { organizationId: record.tenant }),
    ...(record.eventType === undefined ? {} : { eventType: record.eventType }),
    ...(record.category === undefined ? {} : { category: record.category }),
    ...(record.outcome === undefined ? {} : { outcome: record.outcome }),
    ...(record.source === undefined ? {} : { source: record.source }),
    ...(record.targetType === undefined
      ? {}
      : { targetType: record.targetType }),
    ...(record.metadata === undefined ? {} : { metadata: record.metadata }),
  };
}

const CSV_COLUMNS = [
  "id",
  "occurredAt",
  "op",
  "eventType",
  "category",
  "outcome",
  "actorId",
  "actorLabel",
  "actorRole",
  "actorKind",
  "tenant",
  "tenantLabel",
  "table",
  "record",
  "targetType",
  "targetLabel",
  "summary",
  "changed",
  "source",
  "requestId",
  "correlationId",
  "impersonatedBy",
  "metadata",
];

const csvRow = (record: AuditRecord): Record<string, unknown> => ({
  ...record,
  occurredAt: record.occurredAt.toString(),
  changed: record.changed?.join(" "),
});

/**
 * The audit log over the `audit` module's functions, as the caller: the
 * read policy decides what `list` and `export` return, and column mappings
 * of an adopted log are already applied.
 */
export function createAuditLog(options: AuditLogOptions): AuditLog {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const list = (list: AuditListOptions = {}): AsyncResult<AuditPage> => {
    const limit = list.limit ?? 50;
    return call(
      "list_audit_events",
      {
        for_tenant: list.organizationId,
        for_event_type: list.eventType,
        for_actor: list.actorId,
        for_target_type: list.targetType,
        for_record: list.record,
        since: instantArg(list.since),
        until: instantArg(list.until),
        before_at: instantArg(list.before?.occurredAt),
        before_id: list.before?.id,
        max_items: limit,
      },
      (value) => {
        const entries = (Array.isArray(value) ? value : []).map(recordOfEntry);
        const last = entries.at(-1);
        return {
          entries,
          next:
            last === undefined || entries.length < Math.min(limit, 1000)
              ? undefined
              : { occurredAt: last.occurredAt, id: last.id },
        };
      },
    );
  };

  const exportStream = (
    exporting: AuditExportOptions = {},
  ): ReadableStream<Uint8Array> => {
    const format = exporting.format ?? "ndjson";
    const product = exporting.product;
    if (format === "ocsf" && !product) {
      throw new TypeError(
        "createAuditLog().export: the ocsf format needs product",
      );
    }
    const encoder = new TextEncoder();
    let before: AuditCursor | undefined;
    let header = format === "csv";
    let done = false;
    return new ReadableStream<Uint8Array>({
      async pull(controller) {
        if (done) return;
        const page = await list({
          ...exporting,
          ...(before ? { before } : {}),
          limit: exporting.batch ?? 500,
        });
        if (!page.ok) {
          done = true;
          controller.error(new Error(page.error.message));
          return;
        }
        const { entries, next } = page.data;
        let text = "";
        if (format === "csv") {
          const csv = toCsv(entries.map(csvRow), { columns: CSV_COLUMNS });
          text = header ? csv : csv.slice(csv.indexOf("\r\n") + 2);
          header = false;
        } else if (entries.length > 0) {
          text = `${entries
            .map((entry) =>
              JSON.stringify(
                format === "ocsf" && product
                  ? toOcsf(entryOf(entry), product)
                  : entry,
              ),
            )
            .join("\n")}\n`;
        }
        if (text.length > 0) controller.enqueue(encoder.encode(text));
        before = next;
        if (next === undefined) {
          done = true;
          controller.close();
        }
      },
    });
  };

  return {
    list,
    reveal: (entryId) =>
      call("reveal_audit_entry", { entry: entryId }, (value): AuditDetails => {
        const row = isRecord(value) ? value : {};
        const json = (key: string) => {
          const found = row[key];
          return isRecord(found) ? { [key]: found } : {};
        };
        const text = (key: string) => {
          const found = optionalText(row[key]);
          return found === undefined ? {} : { [key]: found };
        };
        return {
          entry: textOf(row["entry"] ?? entryId),
          ...json("old"),
          ...json("new"),
          ...json("metadata"),
          ...text("ip"),
          ...text("userAgent"),
          ...text("sessionId"),
          ...(row["changes"] === undefined || row["changes"] === null
            ? {}
            : { changes: row["changes"] }),
        };
      }),
    export: exportStream,
    exportToStorage: (target) =>
      AsyncResult.from(async () => {
        const format = target.format ?? "ndjson";
        const contentType =
          format === "csv" ? "text/csv" : "application/x-ndjson";
        let body: Blob;
        try {
          body = new Blob(
            [await new Response(exportStream(target)).arrayBuffer()],
            { type: contentType },
          );
        } catch (cause) {
          return err(
            dbError(
              "raised",
              cause instanceof Error ? cause.message : String(cause),
              {
                hint: "AUDIT_EXPORT_FAILED",
              },
            ),
          );
        }
        const bucket = target.storage.from(target.bucket);
        const uploaded = await bucket.upload(target.path, body, {
          contentType,
          upsert: true,
        });
        if (uploaded.error) {
          return err(
            dbError("raised", "The export could not be stored", {
              hint: "AUDIT_EXPORT_FAILED",
            }),
          );
        }
        let url: string | undefined;
        if (target.signedUrlTtl !== undefined && bucket.createSignedUrl) {
          const signed = await bucket.createSignedUrl(
            target.path,
            target.signedUrlTtl,
            { download: true },
          );
          url = signed.data?.signedUrl;
        }
        return ok({ path: target.path, url });
      }),
  };
}
