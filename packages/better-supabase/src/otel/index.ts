import {
  type Attributes,
  context,
  type Histogram,
  type Meter,
  metrics,
  propagation,
  SpanKind,
  SpanStatusCode,
  trace,
  type Tracer,
} from "@opentelemetry/api";

import type { EventHub } from "../core/events.ts";
import type { Executor } from "../core/executor.ts";
import type { Operation } from "../ir/types.ts";

import { blockEventAttributes } from "../core/block-events.ts";
import { definePlugin, type Plugin } from "../core/plugin.ts";
import { SPEC_PINS } from "../core/spec-pins.ts";
import { VERSION } from "../core/version.ts";

export const INSTRUMENTATION_NAME = "better-supabase";
/** OpenTelemetry semantic conventions version the attributes follow. */
export const SEMCONV_VERSION: typeof SPEC_PINS.otelSemconv =
  SPEC_PINS.otelSemconv;

export interface OtelOptions {
  readonly tracer?: Tracer;
  readonly meter?: Meter;
  /** Extra attributes on every span, e.g. `{ 'service.namespace': 'crm' }`. */
  readonly attributes?: Attributes;
  /** Set `false` to skip the duration histogram. */
  readonly metrics?: boolean;
  /**
   * The database name in `db.namespace` (`{database}|{schema}`). Supabase
   * names it `postgres`, the default for Postgres executors.
   */
  readonly database?: string;
  /** `server.address` and `server.port` on spans and metrics, e.g. the project host. */
  readonly server?: { readonly address: string; readonly port?: number };
}

/** A five-character SQLSTATE; PostgREST's own codes (`PGRST116`) are not one. */
const SQLSTATE = /^[0-9A-Z]{5}$/;

function serverAttributes(server: OtelOptions["server"]): Attributes {
  if (!server) return {};
  return server.port === undefined
    ? { "server.address": server.address }
    : { "server.address": server.address, "server.port": server.port };
}

const OPERATION_NAME: { readonly [K in Operation["kind"]]: string } = {
  select: "SELECT",
  insert: "INSERT",
  update: "UPDATE",
  delete: "DELETE",
};

function operationName(op: Operation): string {
  if (op.kind === "insert" && op.onConflict?.action === "update")
    return "UPSERT";
  if (op.kind === "select" && op.head) return "COUNT";
  return OPERATION_NAME[op.kind];
}

function systemOf(executor: Executor): string {
  return executor.name === "postgrest" || executor.name === "postgres"
    ? "postgresql"
    : executor.name;
}

/**
 * Database client spans and metrics for every repository operation, using
 * the OpenTelemetry database conventions. Filter values and row data are
 * never recorded; `db.query.summary` is `SELECT customers`.
 *
 * ```ts
 * const betterSupabase = defineSupabase(schema).use(otel());
 * ```
 */
export function otel(options: OtelOptions = {}): Plugin<"otel"> {
  const tracer =
    options.tracer ?? trace.getTracer(INSTRUMENTATION_NAME, VERSION);
  let histogram: Histogram | undefined;
  if (options.metrics !== false) {
    const meter =
      options.meter ?? metrics.getMeter(INSTRUMENTATION_NAME, VERSION);
    histogram = meter.createHistogram("db.client.operation.duration", {
      unit: "s",
      description: "Duration of database client operations.",
      advice: {
        explicitBucketBoundaries: [
          0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1, 5, 10,
        ],
      },
    });
  }

  return definePlugin({
    name: "otel",
    enforce: "post",
    wrapExecutor: (executor): Executor => {
      const system = systemOf(executor);
      const database =
        options.database ?? (system === "postgresql" ? "postgres" : undefined);
      const server = serverAttributes(options.server);
      /** Span and metric attributes per table and operation, built once. */
      const described = new Map<
        string,
        {
          readonly summary: string;
          readonly attributes: Attributes;
          readonly metric: Attributes;
        }
      >();
      const describe = (op: Operation) => {
        const operation = operationName(op);
        const key = `${op.table.key}:${operation}`;
        let entry = described.get(key);
        if (!entry) {
          const summary = `${operation} ${op.table.name}`;
          entry = {
            summary,
            attributes: {
              ...options.attributes,
              "db.system.name": system,
              "db.namespace": database
                ? `${database}|${op.table.schema}`
                : op.table.schema,
              "db.collection.name": op.table.name,
              "db.operation.name": operation,
              "db.query.summary": summary,
              "better_supabase.executor": executor.name,
              ...server,
            },
            metric: {
              ...server,
              "db.system.name": system,
              "db.collection.name": op.table.name,
              "db.operation.name": operation,
            },
          };
          described.set(key, entry);
        }
        return entry;
      };
      return {
        ...executor,
        name: executor.name,
        execute(op, executeContext) {
          const { summary, attributes, metric } = describe(op);
          const started = performance.now();
          return tracer.startActiveSpan(
            summary,
            { kind: SpanKind.CLIENT, attributes },
            async (span) => {
              const finish = (errorType?: string) => {
                histogram?.record(
                  (performance.now() - started) / 1000,
                  errorType ? { ...metric, "error.type": errorType } : metric,
                );
                span.end();
              };
              try {
                const result = await executor.execute(op, executeContext);
                if (result.ok) {
                  if (span.isRecording())
                    span.setAttribute(
                      "db.response.returned_rows",
                      result.data.rows.length,
                    );
                  finish();
                } else {
                  span.setAttributes({
                    "error.type": result.error.kind,
                    ...(result.error.code && SQLSTATE.test(result.error.code)
                      ? { "db.response.status_code": result.error.code }
                      : {}),
                  });
                  span.setStatus({
                    code: SpanStatusCode.ERROR,
                    message: result.error.message,
                  });
                  finish(result.error.kind);
                }
                return result;
              } catch (cause) {
                const error =
                  cause instanceof Error ? cause : new Error(String(cause));
                span.recordException(error);
                span.setAttribute("error.type", error.name);
                span.setStatus({
                  code: SpanStatusCode.ERROR,
                  message: error.message,
                });
                finish(error.name);
                throw cause;
              }
            },
          );
        },
      };
    },
  });
}

/**
 * Spans for auth resolution and session refreshes, from `betterSupabase.events`.
 * Returns a function that stops listening.
 */
export function traceAuth(
  betterSupabase: { readonly events: EventHub },
  options: Pick<OtelOptions, "tracer" | "attributes"> = {},
): () => void {
  const tracer =
    options.tracer ?? trace.getTracer(INSTRUMENTATION_NAME, VERSION);
  const offAuth = betterSupabase.events.on("auth", (event) => {
    const span = tracer.startSpan("auth.resolve", {
      kind: SpanKind.INTERNAL,
      attributes: {
        ...options.attributes,
        "better_supabase.auth.source": event.source,
        ...(event.userId ? { "enduser.id": event.userId } : {}),
      },
    });
    if (!event.ok) span.setStatus({ code: SpanStatusCode.ERROR });
    span.end();
  });
  const offRefresh = betterSupabase.events.on("refresh", (event) => {
    const end = Date.now();
    const span = tracer.startSpan("auth.refresh", {
      kind: SpanKind.CLIENT,
      startTime: end - event.durationMs,
      attributes: {
        ...options.attributes,
        "better_supabase.refresh.shared": event.shared,
      },
    });
    if (!event.ok) span.setStatus({ code: SpanStatusCode.ERROR });
    span.end(end);
  });
  return () => {
    offAuth();
    offRefresh();
  };
}

/**
 * Records block events (`support.started`, `webhook.failed`, ...) with the
 * `BLOCK_ATTRIBUTES` names: as an event on the active span, or as a short
 * `block <type>` span when there is none. Failures (`*.failed`, `*.denied`)
 * set an error status. Returns a function that stops listening.
 */
export function traceBlockEvents(
  betterSupabase: { readonly events: EventHub },
  options: Pick<OtelOptions, "tracer" | "attributes"> = {},
): () => void {
  const tracer =
    options.tracer ?? trace.getTracer(INSTRUMENTATION_NAME, VERSION);
  return betterSupabase.events.on("block", (event) => {
    const attributes = {
      ...options.attributes,
      ...blockEventAttributes(event),
    };
    const failed =
      event.type.endsWith(".failed") || event.type.endsWith(".denied");
    const active = trace.getActiveSpan();
    if (active) {
      active.addEvent(event.type, attributes);
      return;
    }
    const span = tracer.startSpan(`block ${event.type}`, {
      kind: SpanKind.INTERNAL,
      attributes,
    });
    if (failed) span.setStatus({ code: SpanStatusCode.ERROR });
    span.end();
  });
}

/**
 * A `fetch` that adds W3C `traceparent`/`tracestate` from the active
 * context. Pass it to `createClient(url, key, { global: { fetch } })` so
 * PostgREST, Auth and Storage calls join the trace.
 */
export function tracedFetch(base: typeof fetch = fetch): typeof fetch {
  return (input, init) => {
    const headers = new Headers(
      init?.headers ?? (input instanceof Request ? input.headers : undefined),
    );
    propagation.inject(context.active(), headers, {
      set: (carrier, key, value) => {
        carrier.set(key, value);
      },
    });
    return base(input, { ...init, headers });
  };
}
