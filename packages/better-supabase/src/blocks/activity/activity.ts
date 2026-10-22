import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTenantOptions } from "../../core/block-tenant.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { BetterSupabase } from "../../core/define.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { CloudEvent, EventSink } from "../../events/index.ts";
import type { ListDefinition, ListQueryConfig } from "../../list/list-query.ts";
import type {
  AnyFunctions,
  AnyModels,
  SubjectRef,
  TableKey,
  TableMeta,
} from "../../schema/types.ts";
import type { BlockTemporalOptions, CursorPageOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { optionalSubjectRefOf } from "../../core/block-subjects.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { stripTypePrefix } from "../../events/cloud-event.ts";
import { defineListQuery } from "../../list/list-query.ts";
import {
  applyTemporal,
  blockCall,
  instantArg,
  isRecord,
  optionalText,
  pageOf,
  recordOf,
  recordsOf,
  textOf,
  toInstant,
} from "../shared.ts";

/**
 * Where a timeline entry comes from: `event` for an `activity_entries` row that
 * `activitySink()` wrote, `audit` for an audit log entry on the subject's row
 * (with the `audit` and `subjects` modules), `delivery` for a notification
 * delivery about the subject (with `notifications`) and `run` for a workflow
 * run on it (with `workflows`).
 */
export type ActivitySource = "event" | "audit" | "delivery" | "run";

const ACTIVITY_SOURCES: readonly ActivitySource[] = [
  "event",
  "audit",
  "delivery",
  "run",
];

function sourceOf(value: unknown): ActivitySource {
  return ACTIVITY_SOURCES.find((source) => source === value) ?? "event";
}

export interface ActivityEntry {
  /** An `activity_entries` id, or the audit entry's, delivery's or run's id. */
  readonly id: string;
  readonly source: ActivitySource;
  readonly organizationId: string;
  readonly type: string;
  readonly actorId: string | undefined;
  readonly subject: SubjectRef | undefined;
  readonly summary: string | undefined;
  readonly data: Readonly<Record<string, unknown>>;
  readonly occurredAt: Temporal.Instant;
}

export interface ActivityListOptions extends CursorPageOptions<Temporal.Instant> {
  /** Entries before this instant, for paging back. */
  readonly cursor?: Temporal.Instant;
  /** Default 50, at most 500. */
  readonly limit?: number;
  /** The kinds of entry to return; all of them when left out. */
  readonly sources?: readonly ActivitySource[];
}

export interface ActivityOptions
  extends BlockTemporalOptions, BlockTenantOptions {
  readonly transport: BlockTransport;
  /** The module schema, or its API schema. Default `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  readonly hooks?: BlockHooks<Activity>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

/** Every method acts in the block's `tenant`. */
export interface Activity {
  /**
   * The activity feed of a tenant, newest first, or one subject's timeline with
   * `subject`. Members with `activity.read` see it. With the `subjects` module,
   * an entry on a registered subject type needs `can_subject` read, and a
   * subject's timeline also lists its audit log entries (`source: "audit"`)
   * when `audit` is installed with its read policy, the deliveries of
   * notifications about it (`source: "delivery"`, for members who also hold
   * `notifications.send`) and its workflow runs (`source: "run"`, as the runs'
   * read policy allows).
   */
  list(
    subject?: SubjectRef | null,
    options?: ActivityListOptions,
  ): AsyncResult<readonly ActivityEntry[]>;
}

function activityOf(value: unknown): ActivityEntry {
  const row = recordOf(value, "activity_entries");

  return {
    id: textOf(row["id"]),
    source: sourceOf(row["source"]),
    organizationId: textOf(row["organization_id"]),
    type: textOf(row["type"]),
    actorId: optionalText(row["actor_id"]),
    subject: optionalSubjectRefOf(row["subject_type"], row["subject_id"]),
    summary: optionalText(row["summary"]),
    data: isRecord(row["data"]) ? row["data"] : {},
    occurredAt: toInstant(textOf(row["occurred_at"])),
  };
}

/** The activity feed over the `activity` module's functions, as the caller. */
export function createActivity(options: ActivityOptions): Activity {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const client: Activity = {
    list: (subject, history = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_activity",
          {
            tenant: organizationId,
            subject_type: subject?.type,
            subject_id: subject?.id,
            before: instantArg(pageOf(history).cursor),
            max_rows: history.limit,
            sources: history.sources ? [...history.sources] : undefined,
          },
          (value) => recordsOf(value, "list_activity").map(activityOf),
        ),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "activity",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}

/** What an activity entry says about an event; `null` skips the event. */
export interface ActivityDescription {
  readonly summary?: string;
  readonly actorId?: string;
  readonly subjectType?: string;
  readonly subjectId?: string;
  readonly data?: Readonly<Record<string, unknown>>;
}

export interface ActivitySinkOptions {
  /**
   * A service-role transport: `record_activity()` is granted to `service_role`
   * only.
   */
  readonly transport: BlockTransport;
  readonly schema?: string;
  /**
   * The outbox `typePrefix`, stripped from the stored type. Default
   * `dev.better-supabase`.
   */
  readonly typePrefix?: string;
  /** Types to keep, exact or ending in `.*`. Default every event with a tenant. */
  readonly types?: readonly string[];
  /** Summarizes an event, or returns `null` to skip it. */
  readonly describe?: (
    event: CloudEvent,
    type: string,
  ) => ActivityDescription | null | undefined;
}

const matches = (patterns: readonly string[], type: string): boolean =>
  patterns.some((pattern) =>
    pattern.endsWith(".*")
      ? type.startsWith(pattern.slice(0, -1))
      : pattern === type,
  );

const firstText = (
  data: Readonly<Record<string, unknown>>,
  keys: readonly string[],
): string | undefined => {
  for (const key of keys) {
    const value = optionalText(data[key]);

    if (value !== undefined) {
      return value;
    }
  }

  return undefined;
};

/** `deals/<id>` as `{ type: "deal", id }`, the shape block subjects use. */
function subjectOf(
  subject: string | undefined,
): { type: string; id: string } | undefined {
  const slash = subject?.indexOf("/") ?? -1;

  if (subject === undefined || slash < 1) {
    return undefined;
  }

  const plural = subject.slice(0, slash);

  return {
    type: plural.endsWith("s") ? plural.slice(0, -1) : plural,
    id: subject.slice(slash + 1),
  };
}

/**
 * An outbox sink that writes events into the activity feed:
 * `outbox.relay('activity', activitySink({ transport }))`. Events without a
 * tenant (`partitionkey`) are skipped, and a replayed event writes nothing.
 */
export function activitySink(options: ActivitySinkOptions): EventSink {
  const call = blockCall(options.transport, options.schema);

  return {
    async send(events) {
      const entries: Record<string, unknown>[] = [];

      for (const event of events) {
        const tenant = optionalText(event["partitionkey"]);

        if (tenant === undefined) {
          continue;
        }

        const type = stripTypePrefix(event.type, options.typePrefix);

        if (options.types && !matches(options.types, type)) {
          continue;
        }

        const described = options.describe ? options.describe(event, type) : {};

        if (described === null) {
          continue;
        }

        const data = isRecord(event.data) ? event.data : {};
        const subject = subjectOf(event.subject);
        entries.push({
          event_id: event.id,
          organization_id: tenant,
          type,
          actor_id:
            described?.actorId ??
            firstText(data, ["actorId", "authorId", "userId"]),
          subject_type:
            described?.subjectType ??
            optionalText(data["recordType"]) ??
            optionalText(data["subjectType"]) ??
            subject?.type,
          subject_id:
            described?.subjectId ??
            optionalText(data["recordId"]) ??
            optionalText(data["subjectId"]) ??
            subject?.id,
          summary: described?.summary,
          data: described?.data ?? data,
          occurred_at: event.time,
        });
      }

      if (entries.length > 0) {
        // A sink rejects on failure, so the relay retries the batch.
        await call(
          "record_activity",
          { batch: { entries } },
          () => undefined,
        ).orThrow();
      }
    },
  };
}

export type ActivitySort = "newest" | "oldest";

export type ActivityFacet = "type" | "actor" | "subjectType" | "subjectId";

const FACETS: readonly [ActivityFacet, string, string][] = [
  ["type", "type", "type"],
  ["actor", "actor_id", "actorId"],
  ["subjectType", "subject_type", "subjectType"],
  ["subjectId", "subject_id", "subjectId"],
];

/**
 * A cursor-paged list over `activity_entries` (generate types for the
 * `better_supabase` schema to get it in your models), newest first, filtered by
 * type, actor and subject. Members with `activity.read` see their tenants'
 * entries, less those on a registered subject that `can_subject` doesn't let
 * them read (with the `subjects` module). It reads the table, so it lists no
 * audit entries; `list()` does.
 */
export function activityListQuery<
  M extends AnyModels,
  D,
  Fn extends AnyFunctions,
  E,
  T extends TableKey<M>,
>(
  betterSupabase: BetterSupabase<M, D, Fn, E>,
  table: T,
  options: { readonly pageSize?: number; readonly maxPageSize?: number } = {},
): ListDefinition<M, T, E, ActivitySort, ActivityFacet> {
  const meta: TableMeta | undefined = betterSupabase.meta.tables[table];

  if (!meta) {
    throw new TypeError(`activityListQuery: unknown table "${table}"`);
  }

  const camel = meta.columns["occurredAt"] !== undefined;

  const facets: Record<string, string> = Object.fromEntries(
    FACETS.map(([key, snake, camelName]): [ActivityFacet, string] => [
      key,
      camel ? camelName : snake,
    ]).filter(([, column]) => meta.columns[column] !== undefined),
  );

  const occurredAt = camel ? "occurredAt" : "occurred_at";

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
  } as unknown as ListQueryConfig<
    M,
    T,
    ActivitySort,
    ActivityFacet,
    false,
    "cursor"
  >;

  return defineListQuery(betterSupabase, table, config);
}
