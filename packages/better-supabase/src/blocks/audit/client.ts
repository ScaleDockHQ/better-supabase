import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { EventSink } from "../../events/index.ts";
import type { AuditEntry, OcsfProduct } from "./audit.ts";

import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
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
  pageOf,
} from "../shared.ts";
import { toOcsf } from "./audit.ts";
import { csvPage, revealsDetails, type AuditCsvOptions } from "./csv.ts";
import { auditSink, type AuditSinkOptions } from "./sink.ts";

/** The adopted log's own columns, by column name, as `metadataColumns` maps them. */
export type AuditColumns = Readonly<Record<string, unknown>>;

/**
 * One entry as `list_audit_events` returns it: the module's columns under
 * stable keys, whatever the adopted log calls them. Fields the log doesn't
 * have, or the caller may not read, are missing.
 */
export interface AuditRecord<Columns extends AuditColumns = AuditColumns> {
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
  /**
   * The adopted log's columns that `sql.modules.audit.options.metadataColumns`
   * fills, by column name. Missing without that option.
   */
  readonly columns?: Readonly<Partial<Columns>>;
}

/** Where a page ends: pass it as `before` for the next, older page. */
export interface AuditCursor {
  readonly occurredAt: Temporal.Instant;
  readonly id: string;
}

type OneOrMany = string | readonly string[];

export interface AuditListOptions {
  readonly organizationId?: OneOrMany;
  readonly eventType?: OneOrMany;
  readonly actorId?: OneOrMany;
  readonly targetType?: OneOrMany;
  readonly record?: OneOrMany;
  readonly category?: OneOrMany;
  readonly outcome?: OneOrMany;
  readonly source?: OneOrMany;
  readonly actorKind?: OneOrMany;
  readonly correlationId?: OneOrMany;
  readonly search?: string;
  readonly order?: "desc" | "asc";
  readonly count?: boolean;
  /** Entries at or after this instant. */
  readonly since?: Temporal.Instant;
  /** Entries before this instant. */
  readonly until?: Temporal.Instant;
  /** `page.next` of the previous page; `undefined` starts at the newest. */
  readonly cursor?: AuditCursor | undefined;
  /** @deprecated Use `cursor`. Removed in 0.8. */
  readonly before?: AuditCursor | undefined;
  /** Default 50, at most 1000. */
  readonly limit?: number;
  readonly offset?: number;
}

export interface AuditPage<Columns extends AuditColumns = AuditColumns> {
  readonly entries: readonly AuditRecord<Columns>[];
  /** The cursor of the next page, or `undefined` on the last one. */
  readonly next: AuditCursor | undefined;
  readonly total?: number;
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

export interface AuditExportOptions<Columns extends AuditColumns = AuditColumns>
  extends
    Omit<AuditListOptions, "before" | "limit" | "count">,
    AuditCsvOptions<Columns> {
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

export interface AuditExportToStorageOptions<
  Columns extends AuditColumns = AuditColumns,
> extends AuditExportOptions<Columns> {
  readonly storage: { from(bucket: string): AuditExportBucket };
  readonly bucket: string;
  /** The object path, such as `{organizationId}/audit/{jobId}.csv`. */
  readonly path: string;
  /** Also sign a download URL that lives this many seconds. */
  readonly signedUrlTtl?: number;
}

export interface AuditEventInput {
  readonly eventType: string;
  readonly category?: string;
  readonly outcome?: string;
  readonly source?: string;
  readonly targetType?: string;
  readonly record?: string;
  readonly organizationId?: string;
  readonly metadata?: Readonly<Record<string, unknown>>;
  readonly idempotencyKey?: string;
  readonly restricted?: Readonly<Record<string, unknown>>;
  readonly summary?: string;
  readonly targetLabel?: string;
  readonly correlationId?: string;
  readonly actorId?: string;
  readonly actorKind?: string;
  readonly actorLabel?: string;
  readonly ip?: string;
  readonly userAgent?: string;
  readonly sessionId?: string;
  readonly requestId?: string;
  readonly scope?: string;
}

export interface AuditLogOptions extends BlockTemporalOptions {
  /** `sqlTransport(ctx.postgres)` for members, or `rpcTransport` over an API schema. */
  readonly transport: BlockTransport;
  /** The audit module's schema, or its API schema. Default `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

export interface AuditLog<Columns extends AuditColumns = AuditColumns> {
  record(event: AuditEventInput): AsyncResult<string>;
  /** A page of the entries the caller can read, newest first. */
  list(options?: AuditListOptions): AsyncResult<AuditPage<Columns>>;
  /**
   * The restricted details of one entry for a caller with the reveal
   * permission in its tenant (or platform staff); the reveal is itself
   * recorded as `audit.revealed`. `not_found` otherwise.
   */
  reveal(entryId: string): AsyncResult<AuditDetails>;
  /** Every matching entry as NDJSON, CSV or OCSF, read page by page as the caller. */
  export(options?: AuditExportOptions<Columns>): ReadableStream<Uint8Array>;
  /**
   * Writes an export to a Storage object, for a job that runs it in the
   * background (the data lifecycle export bucket, say), and returns the path
   * and a signed URL when `signedUrlTtl` is set.
   */
  exportToStorage(
    options: AuditExportToStorageOptions<Columns>,
  ): AsyncResult<{ readonly path: string; readonly url: string | undefined }>;
  /**
   * An `EventSink` that records CloudEvents, for `forwardBlockEvents`,
   * `forwardMutations`, an outbox relay or the server's `audit` option.
   * Build the log on a service-role transport so the event's actor counts.
   */
  sink(options?: AuditSinkOptions): EventSink;
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

function recordOfEntry<Columns extends AuditColumns>(
  value: unknown,
): AuditRecord<Columns> {
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
  const columns = json("columns");
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
    ...(columns === undefined
      ? {}
      : {
          // SAFETY: Columns is the caller's description of the adopted columns, which list_audit_events returns by name.
          columns: columns as Partial<Columns>,
        }),
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

const many = (value: OneOrMany | undefined): readonly string[] | undefined =>
  value === undefined ? undefined : typeof value === "string" ? [value] : value;

/** `reveal_audit_entry`'s details, or one of `reveal_audit_entries`'. */
function detailsOf(value: unknown, entryId: string): AuditDetails {
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
}

/**
 * The audit log over the `audit` module's functions, as the caller: the
 * read policy decides what `list` and `export` return, and column mappings
 * of an adopted log are already applied.
 */
export function createAuditLog<Columns extends AuditColumns = AuditColumns>(
  options: AuditLogOptions,
): AuditLog<Columns> {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const list = (
    list: AuditListOptions = {},
  ): AsyncResult<AuditPage<Columns>> => {
    const limit = list.limit ?? 50;
    const filters = {
      for_tenants: many(list.organizationId),
      for_event_types: many(list.eventType),
      for_actors: many(list.actorId),
      for_target_types: many(list.targetType),
      for_records: many(list.record),
      for_categories: many(list.category),
      for_outcomes: many(list.outcome),
      for_sources: many(list.source),
      for_actor_kinds: many(list.actorKind),
      for_correlation_ids: many(list.correlationId),
      search: list.search,
      since: instantArg(list.since),
      until: instantArg(list.until),
    };
    const { cursor } = pageOf(list);
    const page = call(
      "list_audit_events",
      {
        ...filters,
        cursor_at: instantArg(cursor?.occurredAt),
        cursor_id: cursor?.id,
        max_items: limit,
        ascending: list.order === "asc",
        skip: list.offset,
      },
      (value): AuditPage<Columns> => {
        const entries = (Array.isArray(value) ? value : []).map((entry) =>
          recordOfEntry<Columns>(entry),
        );
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
    if (list.count !== true) return page;
    return page.andThen((data) =>
      call("count_audit_events", filters, (value) => ({
        ...data,
        total: Number(value),
      })),
    );
  };

  const revealPage = (
    entries: readonly AuditRecord<Columns>[],
  ): AsyncResult<ReadonlyMap<string, AuditDetails>> =>
    call(
      "reveal_audit_entries",
      { entries: entries.map((entry) => entry.id) },
      (value) =>
        new Map(
          (Array.isArray(value) ? value : []).map((row) => {
            const details = detailsOf(row, "");
            return [details.entry, details] as const;
          }),
        ),
    );

  const exportStream = (
    exporting: AuditExportOptions<Columns> = {},
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
    const {
      offset: start,
      columns,
      preamble,
      formatRow,
      ...filters
    } = exporting;
    const csv = {
      ...(columns === undefined ? {} : { columns }),
      ...(preamble === undefined ? {} : { preamble }),
      ...(formatRow === undefined ? {} : { formatRow }),
    };
    const reveals = format === "csv" && revealsDetails(columns);
    let offset = start;
    let header = format === "csv";
    let done = false;
    return new ReadableStream<Uint8Array>({
      async pull(controller) {
        if (done) return;
        const page = await list({
          ...filters,
          ...(before ? { cursor: before } : {}),
          ...(offset === undefined ? {} : { offset }),
          limit: exporting.batch ?? 500,
        });
        offset = undefined;
        if (!page.ok) {
          done = true;
          controller.error(new Error(page.error.message));
          return;
        }
        const { entries, next } = page.data;
        let text = "";
        if (format === "csv") {
          let details: ReadonlyMap<string, AuditDetails> | undefined;
          if (reveals && entries.length > 0) {
            const revealed = await revealPage(entries);
            if (!revealed.ok) {
              done = true;
              controller.error(new Error(revealed.error.message));
              return;
            }
            details = revealed.data;
          }
          text = csvPage(entries, csv, details, header);
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

  const record = (event: AuditEventInput): AsyncResult<string> =>
    call(
      "audit_event",
      {
        event_type: event.eventType,
        category: event.category,
        outcome: event.outcome,
        source: event.source,
        target_type: event.targetType,
        record_id: event.record,
        tenant: event.organizationId,
        metadata: event.metadata,
        idempotency_key: event.idempotencyKey,
        restricted: event.restricted,
        actor_id: event.actorId,
        summary: event.summary,
        target_label: event.targetLabel,
        correlation_id: event.correlationId,
        actor_kind: event.actorKind,
        actor_label: event.actorLabel,
        ip: event.ip,
        user_agent: event.userAgent,
        session_id: event.sessionId,
        request_id: event.requestId,
        scope: event.scope,
      },
      textOf,
    );

  return {
    record,
    sink: (sinkOptions) => auditSink(record, sinkOptions),
    list,
    reveal: (entryId) =>
      call("reveal_audit_entry", { entry: entryId }, (value) =>
        detailsOf(value, entryId),
      ),
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
