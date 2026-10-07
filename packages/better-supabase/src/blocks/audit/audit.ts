import type { BetterSupabase } from "../../core/define.ts";
import type { WhereInput } from "../../ir/args.ts";
import type { ListDefinition, ListQueryConfig } from "../../list/list-query.ts";
import type { SqlClient } from "../../postgres/executor.ts";
import type {
  AnyFunctions,
  AnyModels,
  TableKey,
  TableMeta,
} from "../../schema/types.ts";

import { type AsyncResult } from "../../core/result.ts";
import { SPEC_PINS } from "../../core/spec-pins.ts";
import { sqlIdent } from "../../core/template.ts";
import { temporal } from "../../core/temporal-required.ts";
import { defineListQuery } from "../../list/list-query.ts";
import {
  instantArg,
  optionalInstant,
  optionalText,
  run,
  seconds,
  stringsOf,
  textOf,
  type BlockTemporalOptions,
  applyTemporal,
} from "../shared.ts";

export interface PurgeAuditLogOptions extends BlockTemporalOptions {
  /** How long entries are kept when `retention` has no answer. Defaults to `1 year`. */
  readonly olderThan?: number | string;
  /** The most entries deleted per tenant in one call. Defaults to 10000. */
  readonly batch?: number;
  /**
   * Days a tenant keeps its entries (a plan's retention, say); `undefined`
   * uses `olderThan`. Called with `null` for entries without a tenant.
   * Retention shorter than a day is not supported. `setAuditRetention`
   * reads the days from a column.
   */
  readonly retention?: (
    tenant: string | null,
  ) => number | undefined | Promise<number | undefined>;
}

/**
 * Deletes audit entries past their retention and returns how many. Without
 * `retention` it is one `purge_audit_log` call (which honours an
 * `audit_retention` SQL hook); with it, each tenant is purged with its own
 * interval. Run it from a schedule until it returns 0.
 */
export function purgeAuditLog(
  sql: SqlClient,
  options: PurgeAuditLogOptions = {},
): AsyncResult<number> {
  applyTemporal(options);
  const olderThan = seconds(options.olderThan ?? "1 year");
  const batch = options.batch ?? 10_000;
  const purge = async (params: unknown[], call: string) => {
    const [row] = await sql.queryRaw<{ n: number | string }>(
      `select better_supabase.purge_audit_log(${call}) as n`,
      params,
    );
    return Number(row?.n ?? 0);
  };
  const { retention } = options;
  if (!retention) {
    return run(() => purge([olderThan, batch], "$1::interval, $2"));
  }
  return run(async () => {
    const tenants = await sql.queryRaw<{ tenant: string | null }>(
      "select tenant::text from better_supabase.audit_events_tenants($1::interval) as tenant",
      ["1 day"],
    );
    let purged = 0;
    for (const { tenant } of tenants) {
      const days = await retention(tenant);
      const keep = days === undefined ? olderThan : `${days} days`;
      purged += await purge(
        [keep, batch, tenant],
        "$1::interval, $2, $3, true",
      );
    }
    return purged;
  });
}

export interface AuditRetentionSource {
  /** `schema.table` holding one row per tenant, e.g. `public.organizations`. */
  readonly table: string;
  /** The integer column with the days to keep; `null` uses `olderThan`. */
  readonly column: string;
  /** The tenant id column. Defaults to `id`. */
  readonly key?: string;
}

/**
 * A `retention` callback for `purgeAuditLog` that reads each tenant's days
 * from a column (a plan's `audit_retention_days`, say), one query per tenant.
 */
export function setAuditRetention(
  sql: SqlClient,
  source: AuditRetentionSource,
): NonNullable<PurgeAuditLogOptions["retention"]> {
  const [schema, name] = source.table.includes(".")
    ? source.table.split(".", 2)
    : ["public", source.table];
  const text = `select ${sqlIdent(source.column)}::integer as days from ${sqlIdent(schema!)}.${sqlIdent(name!)} where ${sqlIdent(source.key ?? "id")}::text = $1`;
  return async (tenant) => {
    if (tenant === null) return;
    const [row] = await sql.queryRaw<{ days: number | null }>(text, [tenant]);
    const days = row?.days;
    return typeof days === "number" && days > 0 ? days : undefined;
  };
}

/** One audit entry as `exportAuditLog` reads it. */
export interface AuditEntry {
  readonly id: string;
  readonly occurredAt: Temporal.Instant;
  /** `insert`, `update` and `delete` for row changes; `event` for `audit_event()`. */
  readonly op: string;
  readonly table?: string;
  readonly record?: string;
  readonly changed?: readonly string[];
  readonly actor?: string;
  readonly actorRole?: string;
  readonly organizationId?: string;
  readonly eventType?: string;
  readonly category?: string;
  readonly outcome?: string;
  readonly source?: string;
  readonly targetType?: string;
  readonly metadata?: Readonly<Record<string, unknown>>;
}

const COLUMNS = [
  "id",
  "occurred_at",
  "op",
  "table_name",
  "record_id",
  "changed",
  "actor_id",
  "actor_role",
  "organization_id",
  "event_type",
  "category",
  "outcome",
  "source",
  "target_type",
  "metadata",
] as const;

function entryOf(row: Readonly<Record<string, unknown>>): AuditEntry {
  const text = (key: string) => optionalText(row[key]);
  const pick = (key: keyof AuditEntry, value: unknown) =>
    value === undefined ? {} : { [key]: value };
  const metadata = row["metadata"];
  return {
    id: textOf(row["id"]),
    occurredAt:
      optionalInstant(row["occurred_at"]) ??
      temporal().Instant.fromEpochMilliseconds(0),
    op: textOf(row["op"]),
    ...pick("table", text("table_name")),
    ...pick("record", text("record_id")),
    ...pick(
      "changed",
      row["changed"] === null || row["changed"] === undefined
        ? undefined
        : stringsOf(row["changed"]),
    ),
    ...pick("actor", text("actor_id")),
    ...pick("actorRole", text("actor_role")),
    ...pick("organizationId", text("organization_id")),
    ...pick("eventType", text("event_type")),
    ...pick("category", text("category")),
    ...pick("outcome", text("outcome")),
    ...pick("source", text("source")),
    ...pick("targetType", text("target_type")),
    ...pick(
      "metadata",
      typeof metadata === "object" &&
        metadata !== null &&
        !Array.isArray(metadata)
        ? metadata
        : undefined,
    ),
  };
}

export interface OcsfProduct {
  readonly name: string;
  readonly vendor_name?: string;
  readonly version?: string;
}

const ENTITY_ACTIVITY: Readonly<Record<string, [number, string]>> = {
  insert: [1, "Create"],
  update: [3, "Update"],
  delete: [4, "Delete"],
};

const API_ACTIVITY: readonly [RegExp, number, string][] = [
  [/(^|[._])(create|created|add|added|insert|inserted)$/, 1, "Create"],
  [/(^|[._])(read|viewed|view|get|list|exported|export)$/, 2, "Read"],
  [/(^|[._])(update|updated|change|changed|rename|renamed)$/, 3, "Update"],
  [/(^|[._])(delete|deleted|remove|removed|revoke|revoked)$/, 4, "Delete"],
];

function status(outcome: string | undefined): {
  status_id: number;
  status: string;
} {
  switch (outcome) {
    case undefined:
    case "success":
    case "succeeded":
      return { status_id: 1, status: "Success" };
    case "failure":
    case "failed":
    case "denied":
      return { status_id: 2, status: "Failure" };
    default:
      return { status_id: 99, status: outcome };
  }
}

/**
 * One entry as an OCSF event (`SPEC_PINS.ocsf`). Row changes are Entity
 * Management (3004); semantic events are API Activity (6003), with the
 * activity read from the event type's last segment (`deal.created` is Create).
 */
export function toOcsf(
  entry: AuditEntry,
  product: OcsfProduct,
): Record<string, unknown> {
  const metadata = {
    version: SPEC_PINS.ocsf,
    product,
    uid: entry.id,
    log_name: "audit_events",
    ...(entry.organizationId ? { tenant_uid: entry.organizationId } : {}),
  };
  const actor = {
    user: {
      uid: entry.actor ?? "system",
      ...(entry.actorRole ? { type: entry.actorRole } : {}),
    },
  };
  const base = {
    severity_id: 1,
    severity: "Informational",
    time: entry.occurredAt.epochMilliseconds,
    ...status(entry.outcome),
    metadata,
    actor,
  };
  const known = ENTITY_ACTIVITY[entry.op];
  if (entry.op !== "event" && known) {
    const [activity, name] = known;
    return {
      class_uid: 3004,
      class_name: "Entity Management",
      category_uid: 3,
      category_name: "Identity & Access Management",
      activity_id: activity,
      activity_name: name,
      type_uid: 3004 * 100 + activity,
      ...base,
      entity: {
        uid: entry.record ?? "",
        type: entry.table ?? "row",
      },
      ...(entry.changed ? { unmapped: { changed: entry.changed } } : {}),
    };
  }
  const operation = entry.eventType ?? entry.op;
  const match = API_ACTIVITY.find(([pattern]) => pattern.test(operation));
  const [activity, name] = match ? [match[1], match[2]] : [99, operation];
  return {
    class_uid: 6003,
    class_name: "API Activity",
    category_uid: 6,
    category_name: "Application Activity",
    activity_id: activity,
    activity_name: name,
    type_uid: 6003 * 100 + activity,
    ...base,
    api: { operation },
    src_endpoint: { name: entry.source ?? "database" },
    ...(entry.record || entry.targetType
      ? {
          resources: [
            {
              uid: entry.record ?? "",
              type: entry.targetType ?? entry.table ?? "resource",
            },
          ],
        }
      : {}),
    ...(entry.metadata || entry.category
      ? {
          unmapped: {
            ...(entry.category ? { category: entry.category } : {}),
            ...(entry.metadata ? { metadata: entry.metadata } : {}),
          },
        }
      : {}),
  };
}

export interface ExportAuditLogOptions extends BlockTemporalOptions {
  /** Only this tenant's entries. */
  readonly organizationId: string;
  readonly from?: Temporal.Instant;
  /** Exclusive. */
  readonly to?: Temporal.Instant;
  /** `ndjson` writes entries as they are; `ocsf` maps each with `toOcsf`. */
  readonly format?: "ndjson" | "ocsf";
  /** Required for `ocsf`: `metadata.product`. */
  readonly product?: OcsfProduct;
  /** Rows per query. Defaults to 1000. */
  readonly batch?: number;
  /** Defaults to `better_supabase.audit_events`. */
  readonly table?: string;
}

/**
 * Streams one tenant's audit entries as newline-delimited JSON, in id
 * order, one keyset query per batch. Run it with a member's claims (the
 * `readPolicy` filters) or as the service role. It reads the managed
 * module's column names; for an adopted log, the version 3 columns or CSV,
 * use `createAuditLog().export()`, which reads `list_audit_events`.
 */
export function exportAuditLog(
  sql: SqlClient,
  options: ExportAuditLogOptions,
): ReadableStream<Uint8Array> {
  applyTemporal(options);
  const format = options.format ?? "ndjson";
  if (format === "ocsf" && !options.product) {
    throw new TypeError("exportAuditLog: the ocsf format needs product");
  }
  const batch = options.batch ?? 1000;
  const [schema, name] = (
    options.table ?? "better_supabase.audit_events"
  ).split(".", 2);
  const text = `select ${COLUMNS.map((column) => sqlIdent(column)).join(", ")}
from ${sqlIdent(schema!)}.${sqlIdent(name!)}
where organization_id::text = $1
  and ($2::timestamptz is null or occurred_at >= $2)
  and ($3::timestamptz is null or occurred_at < $3)
  and id > $4
order by id
limit $5`;
  const encoder = new TextEncoder();
  let after = "0";
  let done = false;
  return new ReadableStream<Uint8Array>({
    async pull(controller) {
      if (done) return;
      const rows = await sql.queryRaw(text, [
        options.organizationId,
        instantArg(options.from) ?? null,
        instantArg(options.to) ?? null,
        after,
        batch,
      ]);
      const lines = rows.map((row) => {
        const entry = entryOf(row);
        return JSON.stringify(
          format === "ocsf" ? toOcsf(entry, options.product!) : entry,
        );
      });
      if (lines.length > 0) {
        controller.enqueue(encoder.encode(`${lines.join("\n")}\n`));
        after = textOf(rows.at(-1)!["id"]);
      }
      if (rows.length < batch) {
        done = true;
        controller.close();
      }
    },
  });
}

export type AuditSort = "newest" | "oldest";
export type AuditFacet =
  | "table"
  | "record"
  | "op"
  | "actor"
  | "event"
  | "category"
  | "outcome"
  | "target";

const FACETS: readonly [AuditFacet, string, string][] = [
  ["table", "table_name", "tableName"],
  ["record", "record_id", "recordId"],
  ["op", "op", "op"],
  ["actor", "actor_id", "actorId"],
  ["event", "event_type", "eventType"],
  ["category", "category", "category"],
  ["outcome", "outcome", "outcome"],
  ["target", "target_type", "targetType"],
];

export type AuditListDefinition<
  M extends AnyModels,
  T extends TableKey<M>,
  E,
> = ListDefinition<M, T, E, AuditSort, AuditFacet, false, "cursor"> & {
  /** A `where` for `run(db, query, { where })`: entries in `[from, to)`. */
  between(from?: Temporal.Instant, to?: Temporal.Instant): WhereInput<M, T>;
};

/**
 * A cursor-paged list over the audit table through the Data API or
 * `ctx.sql` (generate types for the module's schema to get it in your
 * models; facets follow the managed column names). `createAuditLog().list()`
 * reads `list_audit_events` instead, with an adopted log's columns mapped.
 * Filtered by actor,
 * table, record, event type, category, outcome and target, newest first.
 * The `readPolicy` and the `restricted` table decide what a member sees.
 */
export function auditListQuery<
  M extends AnyModels,
  D,
  Fn extends AnyFunctions,
  E,
  T extends TableKey<M>,
>(
  betterSupabase: BetterSupabase<M, D, Fn, E>,
  table: T,
  options: { readonly pageSize?: number; readonly maxPageSize?: number } = {},
): AuditListDefinition<M, T, E> {
  const meta: TableMeta | undefined = betterSupabase.meta.tables[table];
  if (!meta) throw new TypeError(`auditListQuery: unknown table "${table}"`);
  const camel = meta.columns["occurredAt"] !== undefined;
  const col = (snake: string, camelName: string) => (camel ? camelName : snake);
  const facets: Record<string, string> = Object.fromEntries(
    FACETS.map(([key, snake, camelName]): [AuditFacet, string] => [
      key,
      col(snake, camelName),
    ]).filter(([, column]) => meta.columns[column] !== undefined),
  );
  const occurredAt = col("occurred_at", "occurredAt");
  // SAFETY: defineListQuery checks every column against the table's meta
  // and throws for one the table lacks; facets keeps only columns it has.
  // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- the column names are known only at runtime (camel or snake casing), so the config can't be typed against M.
  const config = {
    facets,
    sorts: {
      newest: [{ [occurredAt]: "desc" }, { id: "desc" }],
      oldest: [{ [occurredAt]: "asc" }, { id: "asc" }],
    },
    defaultSort: "newest",
    pagination: "cursor",
    ...(options.pageSize === undefined ? {} : { pageSize: options.pageSize }),
    ...(options.maxPageSize === undefined
      ? {}
      : { maxPageSize: options.maxPageSize }),
  } as unknown as ListQueryConfig<M, T, AuditSort, AuditFacet, false, "cursor">;
  const list = defineListQuery(betterSupabase, table, config);
  return Object.assign(list, {
    between(from?: Temporal.Instant, to?: Temporal.Instant): WhereInput<M, T> {
      const range = {
        ...(from ? { gte: from.toString() } : {}),
        ...(to ? { lt: to.toString() } : {}),
      };
      // SAFETY: occurredAt is a timestamptz column of the audit table; the
      // repository validates the filter against its meta.
      return (
        Object.keys(range).length === 0 ? {} : { [occurredAt]: range }
      ) as WhereInput<M, T>;
    },
  });
}
