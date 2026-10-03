import {
  type Attributes,
  type Meter,
  type Span,
  type SpanOptions,
  SpanKind,
  SpanStatusCode,
  type Tracer,
} from "@opentelemetry/api";
import { describe, expect, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";
import { otel, SEMCONV_VERSION } from "../../src/otel/index.ts";
import { capturingClient } from "../fixtures/client.ts";
import { schema } from "../fixtures/generated-camel.ts";

interface Recorded {
  name: string;
  kind: SpanKind | undefined;
  attributes: Attributes;
  status?: { code: SpanStatusCode };
}

function recorder() {
  const spans: Recorded[] = [];
  const histograms: { name: string; unit?: string }[] = [];
  const metrics: Attributes[] = [];
  const startActiveSpan = (
    name: string,
    options: SpanOptions,
    fn: (span: Span) => unknown,
  ) => {
    const record: Recorded = {
      name,
      kind: options.kind,
      attributes: { ...options.attributes },
    };
    spans.push(record);
    const span = {
      setAttribute: (key: string, value: never) => (
        (record.attributes[key] = value),
        span
      ),
      setAttributes: (values: Attributes) => (
        Object.assign(record.attributes, values),
        span
      ),
      setStatus: (status: { code: SpanStatusCode }) => (
        (record.status = status),
        span
      ),
      recordException: () => undefined,
      isRecording: () => true,
      end: () => undefined,
    };
    return fn(span as unknown as Span);
  };
  const meter = {
    createHistogram: (name: string, options?: { unit?: string }) => {
      histograms.push({
        name,
        ...(options?.unit ? { unit: options.unit } : {}),
      });
      return {
        record: (_value: number, attributes?: Attributes) =>
          metrics.push(attributes ?? {}),
      };
    },
  } as unknown as Meter;
  return {
    tracer: { startActiveSpan } as unknown as Tracer,
    meter,
    spans,
    histograms,
    metrics,
  };
}

/** Attribute names defined by the 1.37.0 database conventions (and `error.type` from the general registry). */
const DB_SPAN_ATTRIBUTES = new Set([
  "db.system.name",
  "db.namespace",
  "db.collection.name",
  "db.operation.name",
  "db.query.summary",
  "db.response.status_code",
  "db.response.returned_rows",
  "error.type",
]);

describe(`OpenTelemetry database semantic conventions ${SPEC_PINS.otelSemconv}`, () => {
  it("SEMCONV_VERSION is SPEC_PINS.otelSemconv", () => {
    expect(SEMCONV_VERSION).toBe(SPEC_PINS.otelSemconv);
  });

  it("a successful operation is a CLIENT span named by db.query.summary with only registered attributes", async () => {
    const { tracer, meter, spans } = recorder();
    const betterSupabase = defineSupabase(schema).use(otel({ tracer, meter }));
    const { client } = capturingClient(() => ({
      body: [{ id: "c1" }, { id: "c2" }],
    }));
    await betterSupabase
      .connect(client)
      .customers.findMany({ where: { name: "secret" }, select: ["id"] })
      .orThrow();
    const [span] = spans;
    expect(span!.kind).toBe(SpanKind.CLIENT);
    expect(span!.name).toBe(span!.attributes["db.query.summary"]);
    expect(span!.attributes).toMatchObject({
      "db.system.name": "postgresql",
      "db.namespace": "public",
      "db.collection.name": "customers",
      "db.operation.name": "SELECT",
      "db.query.summary": "SELECT customers",
      "db.response.returned_rows": 2,
    });
    for (const key of Object.keys(span!.attributes).filter(
      (name) => !name.startsWith("better_supabase."),
    ))
      expect(DB_SPAN_ATTRIBUTES).toContain(key);
    expect(span!.status).toBeUndefined();
  });

  it("never records db.query.text or filter values (opt-in attributes stay off)", async () => {
    const { tracer, meter, spans } = recorder();
    const betterSupabase = defineSupabase(schema).use(otel({ tracer, meter }));
    const { client } = capturingClient(() => ({ body: [] }));
    await betterSupabase
      .connect(client)
      .customers.findMany({ where: { name: "secret value" } });
    expect(JSON.stringify(spans)).not.toContain("secret value");
    expect(spans[0]!.attributes).not.toHaveProperty("db.query.text");
  });

  it("a failed operation sets error.type, db.response.status_code and status ERROR", async () => {
    const { tracer, meter, spans, metrics } = recorder();
    const betterSupabase = defineSupabase(schema).use(otel({ tracer, meter }));
    const { client } = capturingClient(() => ({
      status: 409,
      body: {
        code: "23505",
        message: "duplicate key value",
        details: null,
        hint: null,
      },
    }));
    await betterSupabase
      .connect(client)
      .customers.create({ name: "Acme", organizationId: "o1" });
    expect(spans[0]!.attributes).toMatchObject({
      "db.operation.name": "INSERT",
      "error.type": "conflict",
      "db.response.status_code": "23505",
    });
    expect(spans[0]!.status?.code).toBe(SpanStatusCode.ERROR);
    expect(metrics[0]).toMatchObject({ "error.type": "conflict" });
  });

  it("records db.client.operation.duration in seconds with the low-cardinality attributes", async () => {
    const { tracer, meter, histograms, metrics } = recorder();
    const betterSupabase = defineSupabase(schema).use(otel({ tracer, meter }));
    const { client } = capturingClient(() => ({ body: [] }));
    await betterSupabase.connect(client).customers.findMany();
    expect(histograms).toEqual([
      { name: "db.client.operation.duration", unit: "s" },
    ]);
    expect(Object.keys(metrics[0]!).toSorted()).toEqual([
      "db.collection.name",
      "db.operation.name",
      "db.system.name",
    ]);
  });
});
