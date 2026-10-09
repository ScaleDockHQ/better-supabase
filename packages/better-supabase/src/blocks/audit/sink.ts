import type { AsyncResult } from "../../core/result.ts";
import type { CloudEvent, EventSink } from "../../events/index.ts";
import type { AuditEventInput } from "./client.ts";

import { DbException } from "../../core/errors.ts";
import { isRecord } from "../shared.ts";

export interface AuditSinkOptions {
  /** The type prefix stripped from each event's `type`. Defaults to `dev.better-supabase`. */
  readonly typePrefix?: string;
}

const textIn = (value: unknown): string | undefined =>
  typeof value === "string" && value !== "" ? value : undefined;

/**
 * The audit entry for one CloudEvent: its type without the prefix, its
 * subject as the record, the tenant from the `tenant` or `partitionkey`
 * extension (or `data.organizationId`), and the data as metadata. The
 * idempotency key is the event's source and id, so a redelivery records once.
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
  return {
    eventType: event.type.startsWith(prefix)
      ? event.type.slice(prefix.length)
      : event.type,
    idempotencyKey: `${event.source}#${event.id}`,
    ...(event.subject === undefined ? {} : { record: event.subject }),
    ...(organizationId === undefined ? {} : { organizationId }),
    ...(actorId === undefined ? {} : { actorId }),
    ...(metadata === undefined ? {} : { metadata }),
  };
}

/**
 * An `EventSink` that records each CloudEvent in the audit log. `send`
 * throws when an entry fails, so an outbox relay retries the batch; the
 * idempotency key keeps the entries already written from repeating.
 */
export function auditSink(
  record: (event: AuditEventInput) => AsyncResult<string>,
  options: AuditSinkOptions = {},
): EventSink {
  return {
    async send(events) {
      let failure: DbException | undefined;
      for (const event of events) {
        const result = await record(auditEventOf(event, options));
        if (!result.ok) failure ??= new DbException(result.error);
      }
      if (failure !== undefined) throw failure;
    },
  };
}
