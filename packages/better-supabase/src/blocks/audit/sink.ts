import type { AsyncResult, Result } from "../../core/result.ts";
import type { CloudEvent, EventSink } from "../../events/cloud-event.ts";
import type { AuditCategory } from "../../sql/context.ts";
import type { AuditEventInput } from "./audit-log.ts";

import { MAX_BATCH } from "../../core/batch-limit.ts";
import { DbException } from "../../core/errors.ts";
import { chunksOf, isRecord } from "../shared.ts";

export interface AuditSinkOptions {
  /**
   * The type prefix stripped from each event's `type`. Defaults to
   * `dev.better-supabase`.
   */
  readonly typePrefix?: string;
  /**
   * The category for an event type (without the prefix), from the categories
   * the SQL modules use. Defaults to `security` for `account.*` and
   * `support.*`, and no category for the rest.
   */
  readonly category?: (eventType: string) => AuditCategory | undefined;
}

const textIn = (value: unknown): string | undefined =>
  typeof value === "string" && value !== "" ? value : undefined;

const defaultCategory = (eventType: string): AuditCategory | undefined =>
  eventType.startsWith("account.") || eventType.startsWith("support.")
    ? "security"
    : undefined;

/**
 * The impersonation fields of a `support.*` event: its session, admin and
 * reason.
 */
function supportFields(
  eventType: string,
  data: Readonly<Record<string, unknown>> | undefined,
): Pick<
  AuditEventInput,
  "supportSessionId" | "impersonatedBy" | "impersonationReason"
> {
  if (!eventType.startsWith("support.") || data === undefined) {
    return {};
  }

  const sessionId = textIn(data["sessionId"]);
  const adminId = textIn(data["adminId"]);
  const reason = textIn(data["reason"]);

  return {
    ...(sessionId === undefined ? {} : { supportSessionId: sessionId }),
    ...(adminId === undefined ? {} : { impersonatedBy: adminId }),
    ...(reason === undefined ? {} : { impersonationReason: reason }),
  };
}

/**
 * The audit entry for one CloudEvent: its type without the prefix, its subject
 * as the record, the tenant from the `tenant` or `partitionkey` extension (or
 * `data.organizationId`), and the data as metadata. The idempotency key is the
 * event's source and id, so a redelivery records once. A `support.*` event also
 * fills the impersonation columns from its `sessionId`, `adminId` and
 * `reason`.
 */
export function auditEventOf(
  event: CloudEvent,
  options: AuditSinkOptions = {},
): AuditEventInput {
  const prefix = `${options.typePrefix ?? "dev.better-supabase"}.`;
  const data = isRecord(event.data) ? event.data : undefined;

  const organizationId =
    textIn(event["tenant"]) ??
    textIn(event["partitionkey"]) ??
    textIn(data?.["organizationId"]);

  const actorId = textIn(data?.["actorId"]);

  const metadata =
    data ?? (event.data === undefined ? undefined : { data: event.data });

  const eventType = event.type.startsWith(prefix)
    ? event.type.slice(prefix.length)
    : event.type;

  const category = (options.category ?? defaultCategory)(eventType);

  return {
    eventType,
    idempotencyKey: `${event.source}#${event.id}`,
    ...(category === undefined ? {} : { category }),
    ...(event.subject === undefined ? {} : { record: event.subject }),
    ...(organizationId === undefined ? {} : { organizationId }),
    ...(actorId === undefined ? {} : { actorId }),
    ...(metadata === undefined ? {} : { metadata }),
    ...supportFields(eventType, data),
  };
}

/**
 * An `EventSink` that records CloudEvents in the audit log, one `recordMany`
 * call per chunk of at most `MAX_BATCH` events. `send` throws the first failure
 * once every chunk ran, so an outbox relay retries the batch; the idempotency
 * key keeps the entries already written from repeating.
 */
export function auditSink(
  recordMany: (
    events: readonly AuditEventInput[],
  ) => AsyncResult<readonly Result<string>[]>,
  options: AuditSinkOptions = {},
): EventSink {
  return {
    async send(events) {
      let failure: DbException | undefined;

      for (const chunk of chunksOf(events, MAX_BATCH)) {
        const results = await recordMany(
          chunk.map((event) => auditEventOf(event, options)),
        );

        if (!results.ok) {
          failure ??= new DbException(results.error);
          continue;
        }

        for (const result of results.data) {
          if (!result.ok) {
            failure ??= new DbException(result.error);
          }
        }
      }

      if (failure !== undefined) {
        throw failure;
      }
    },
  };
}
