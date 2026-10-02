import {
  type Attributes,
  context,
  type Meter,
  propagation,
  type Span,
  type SpanOptions,
  SpanStatusCode,
  type TextMapPropagator,
  trace,
  type Tracer,
} from "@opentelemetry/api";
import { afterEach, describe, expect, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { EventHub } from "../../src/core/events.ts";
import { otel, traceAuth, tracedFetch } from "../../src/otel/index.ts";
import { capturingClient } from "../fixtures/client.ts";
import { schema } from "../fixtures/generated-camel.ts";

interface Recorded {
  name: string;
  attributes: Attributes;
  status?: { code: SpanStatusCode; message?: string };
  ended: boolean;
  startTime?: unknown;
}

function memoryTracer() {
  const spans: Recorded[] = [];
  const make = (name: string, options?: SpanOptions): Span => {
    const record: Recorded = {
      name,
      attributes: { ...options?.attributes },
      ended: false,
      startTime: options?.startTime,
    };
    spans.push(record);
    const span = {
      setAttribute: (key: string, value: unknown) => {
        record.attributes[key] = value as never;
        return span;
      },
      setAttributes: (values: Attributes) => {
        Object.assign(record.attributes, values);
        return span;
      },
      setStatus: (status: { code: SpanStatusCode; message?: string }) => {
        record.status = status;
        return span;
      },
      recordException: () => undefined,
      end: () => {
        record.ended = true;
      },
    };
    return span as unknown as Span;
  };
  const tracer = {
    startSpan: make,
    startActiveSpan: (
      name: string,
      options: SpanOptions,
      fn: (span: Span) => unknown,
    ) => fn(make(name, options)),
  } as unknown as Tracer;
  return { tracer, spans };
}

function memoryMeter() {
  const records: { value: number; attributes: Attributes | undefined }[] = [];
  const meter = {
    createHistogram: () => ({
      record: (value: number, attributes?: Attributes) =>
        records.push({ value, attributes }),
    }),
  } as unknown as Meter;
  return { meter, records };
}

describe("otel", () => {
  afterEach(() => {
    propagation.disable();
  });

  it("records a client span per operation without filter values", async () => {
    const { tracer, spans } = memoryTracer();
    const { meter, records } = memoryMeter();
    const sb = defineSupabase(schema).use(otel({ tracer, meter }));
    const { client } = capturingClient(() => ({ body: [{ id: "c1" }] }));
    await sb
      .connect(client)
      .customers.findMany({ where: { name: "secret value" }, select: ["id"] })
      .orThrow();
    expect(spans).toEqual([
      {
        name: "SELECT customers",
        attributes: {
          "db.system.name": "postgresql",
          "db.namespace": "public",
          "db.collection.name": "customers",
          "db.operation.name": "SELECT",
          "db.query.summary": "SELECT customers",
          "better_supabase.executor": "postgrest",
          "db.response.returned_rows": 1,
        },
        ended: true,
        startTime: undefined,
      },
    ]);
    expect(JSON.stringify(spans)).not.toContain("secret");
    expect(records).toHaveLength(1);
    expect(records[0]?.attributes).toEqual({
      "db.system.name": "postgresql",
      "db.collection.name": "customers",
      "db.operation.name": "SELECT",
    });
  });

  it("marks failed operations", async () => {
    const { tracer, spans } = memoryTracer();
    const sb = defineSupabase(schema).use(otel({ tracer, metrics: false }));
    const { client } = capturingClient(() => ({
      status: 409,
      body: { code: "23505", message: "duplicate key value" },
    }));
    const result = await sb
      .connect(client)
      .customers.create({ organizationId: "o1", name: "A" });
    expect(result.error?.kind).toBe("conflict");
    expect(spans[0]).toMatchObject({
      name: "INSERT customers",
      attributes: {
        "error.type": "conflict",
        "db.response.status_code": "23505",
      },
      status: { code: SpanStatusCode.ERROR },
      ended: true,
    });
  });

  it("traces auth events", () => {
    const { tracer, spans } = memoryTracer();
    const events = new EventHub();
    const stop = traceAuth({ events }, { tracer });
    events.emit("auth", { source: "cookie", ok: true, userId: "u1" });
    events.emit("refresh", { ok: false, shared: true, durationMs: 25 });
    stop();
    events.emit("auth", { source: "none", ok: true });
    expect(spans.map((span) => [span.name, span.status?.code])).toEqual([
      ["auth.resolve", undefined],
      ["auth.refresh", SpanStatusCode.ERROR],
    ]);
    expect(spans[0]?.attributes).toMatchObject({
      "enduser.id": "u1",
      "better_supabase.auth.source": "cookie",
    });
  });

  it("propagates traceparent through fetch", async () => {
    const propagator: TextMapPropagator = {
      inject: (_context, carrier, setter) => {
        setter.set(
          carrier,
          "traceparent",
          "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01",
        );
      },
      extract: (value) => value,
      fields: () => ["traceparent"],
    };
    propagation.setGlobalPropagator(propagator);
    let seen: Headers | undefined;
    const fetch = tracedFetch(async (_input, init) => {
      seen = new Headers(init?.headers);
      return new Response(null, { status: 204 });
    });
    await context.with(
      trace.setSpanContext(
        context.active(),
        trace
          .wrapSpanContext({
            traceId: "a".repeat(32),
            spanId: "b".repeat(16),
            traceFlags: 1,
          })
          .spanContext(),
      ),
      () => fetch("http://localhost/rest/v1/x", { headers: { apikey: "k" } }),
    );
    expect(seen?.get("traceparent")).toMatch(/^00-/);
    expect(seen?.get("apikey")).toBe("k");
  });
});
