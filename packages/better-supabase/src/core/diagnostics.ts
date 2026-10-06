import { EventHub } from "./events.ts";
import { consoleLogger, type LogFields, type Logger } from "./logger.ts";

/**
 * Debug records for the `diagnostics` option, after the Supabase SDK
 * capability `client.observability.diagnostic_logging`
 * (`SPEC_PINS.supabaseSdkCapabilities`). Fields are names, kinds, counts and
 * timings only: never tokens, keys, row values, filters, query strings,
 * headers or database error messages, which can quote the data.
 */
function logDiagnostics(events: EventHub): void {
  const logger = {
    debug(message: string, fields: LogFields): void {
      try {
        events.logger.debug(message, fields);
      } catch {
        // A diagnostic record must never change the outcome it describes.
      }
    },
  };
  events.on("query", (event) => {
    logger.debug(
      `${event.operation} ${event.table} ${event.ok ? "ok" : "failed"} in ${String(Math.round(event.durationMs))}ms`,
      {
        table: event.table,
        operation: event.operation,
        ok: event.ok,
        durationMs: event.durationMs,
        rows: event.rows,
        truncated: event.truncated,
      },
    );
  });
  events.on("error", ({ table, error }) => {
    logger.debug(`${error.kind} error${table ? ` on ${table}` : ""}`, {
      ...(table ? { table } : {}),
      kind: error.kind,
      status: error.status,
      ...(error.code ? { code: error.code } : {}),
    });
  });
  events.on("refresh", (event) => {
    logger.debug(
      `session refresh ${event.ok ? "ok" : "failed"} in ${String(Math.round(event.durationMs))}ms`,
      { ok: event.ok, shared: event.shared, durationMs: event.durationMs },
    );
  });
  events.on("auth", (event) => {
    logger.debug(
      `auth from ${event.source}: ${event.ok ? "user" : (event.reason ?? "no user")}`,
      {
        source: event.source,
        ok: event.ok,
        ...(event.reason ? { reason: event.reason } : {}),
      },
    );
  });
}

/** The event hub of a new definition, with the diagnostic handlers when `diagnostics` is on. */
export function definitionEvents(options: {
  readonly logger?: Logger;
  readonly diagnostics?: boolean;
}): EventHub {
  const events = new EventHub(options.logger ?? consoleLogger);
  if (options.diagnostics === true) logDiagnostics(events);
  return events;
}
