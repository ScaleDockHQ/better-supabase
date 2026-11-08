import type { Attributes, Span, SpanOptions, Tracer } from "@opentelemetry/api";

import { SpanStatusCode } from "@opentelemetry/api";
import { describe, expect, it } from "vitest";

import { createSupabase } from "../../src/core/define.ts";
import { dbError } from "../../src/core/errors.ts";
import { EventHub } from "../../src/core/events.ts";
import { err, ok } from "../../src/core/result.ts";
import {
  otel,
  traceAuth,
  tracedFetch,
  traceBlockEvents,
} from "../../src/otel/index.ts";
import { schema } from "../fixtures/generated-camel.ts";

interface Recorded {
  name: string;
  attributes: Attributes;
  status?: { code: SpanStatusCode; message?: string };
  exceptions: unknown[];
  recording: boolean;
}

function memoryTracer(recording = true) {
  const spans: Recorded[] = [];

  const make = (name: string, options?: SpanOptions): Span => {
    const record: Recorded = {
      name,
      attributes: { ...options?.attributes },
      exceptions: [],
      recording,
    };

    spans.push(record);

    const span = {
      setAttribute: (key: string, value: unknown) => {
        // SAFETY: the memory span stores any attribute value as given.
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
      recordException: (exception: unknown) => {
        record.exceptions.push(exception);
      },
      isRecording: () => recording,
      end: () => undefined,
    };

    // SAFETY: only the Span members the plugin calls are implemented.
    return span as unknown as Span;
  };

  const tracer = {
    startSpan: make,
    startActiveSpan: (
      name: string,
      options: SpanOptions,
      fn: (span: Span) => unknown,
    ) => fn(make(name, options)),
    // SAFETY: only the Tracer members the plugin calls are implemented.
  } as unknown as Tracer;

  return { tracer, spans };
}

const empty = async () => ok({ rows: [], count: null });

describe("otel operation names", () => {
  it("names upsert, update, delete and count operations", async () => {
    const { tracer, spans } = memoryTracer();

    const betterSupabase = createSupabase(schema).use(
      otel({ tracer, metrics: false, attributes: { team: "crm" } }),
    );

    const db = betterSupabase.connect({ name: "postgrest", execute: empty });

    await db.customers.upsert(
      { organizationId: "o1", name: "A", kvk: "1" },
      { onConflict: "customers_organization_id_kvk_key", select: ["id"] },
    );
    await db.customers.update("c1", { name: "B" });
    await db.customers.delete({ where: { status: "lead" } });
    await db.customers.count({ where: { status: "active" } });

    const names = spans.map((span) => span.name);

    expect(names).toContain("UPSERT customers");
    expect(names).toContain("UPDATE customers");
    expect(names).toContain("DELETE customers");
    expect(names).toContain("COUNT customers");
    expect(spans[0]?.attributes).toMatchObject({ team: "crm" });
  });

  it("does not record the row count on a span that is not recording", async () => {
    const { tracer, spans } = memoryTracer(false);

    const betterSupabase = createSupabase(schema).use(
      otel({ tracer, metrics: false }),
    );

    const db = betterSupabase.connect({
      name: "postgrest",
      execute: async () => ok({ rows: [{ id: "c1" }], count: null }),
      batch: async (ops) => ops.map(() => ok({ rows: [], count: null })),
    });

    await db.customers.list({ select: ["id"] });
    await db.$many([
      betterSupabase.spec.customers.list({ select: ["id"] }),
      betterSupabase.spec.customers.list({ select: ["id"] }),
    ]);

    for (const span of spans) {
      expect(span.attributes).not.toHaveProperty("db.response.returned_rows");
    }
  });
});

describe("otel failures", () => {
  it("records a thrown error on the span", async () => {
    const { tracer, spans } = memoryTracer();

    const betterSupabase = createSupabase(schema).use(
      otel({ tracer, metrics: false }),
    );

    const boom = new TypeError("socket closed");

    const db = betterSupabase.connect({
      name: "postgrest",
      execute: () => {
        throw boom;
      },
    });

    const result = await db.customers.list({ select: ["id"] });

    expect(result.error?.message).toBe("socket closed");
    expect(spans[0]?.exceptions).toEqual([boom]);
    expect(spans[0]?.attributes["error.type"]).toBe("TypeError");
    expect(spans[0]?.status).toEqual({
      code: SpanStatusCode.ERROR,
      message: "socket closed",
    });
  });

  it("wraps a thrown non-error value", async () => {
    const { tracer, spans } = memoryTracer();

    const betterSupabase = createSupabase(schema).use(
      otel({ tracer, metrics: false }),
    );

    const db = betterSupabase.connect({
      name: "postgrest",
      execute: () => Promise.reject("plain string"),
    });

    const result = await db.customers.list({ select: ["id"] });

    expect(result.error?.message).toBe("plain string");
    expect(spans[0]?.attributes["error.type"]).toBe("Error");
    expect(spans[0]?.status?.message).toBe("plain string");
  });

  it("omits the status code for an error without a code", async () => {
    const { tracer, spans } = memoryTracer();

    const betterSupabase = createSupabase(schema).use(
      otel({ tracer, metrics: false }),
    );

    const db = betterSupabase.connect({
      name: "postgrest",
      execute: async () => err(dbError("timeout", "slow")),
    });

    await db.customers.list({ select: ["id"] });
    expect(spans[0]?.attributes).not.toHaveProperty("db.response.status_code");
  });
});

describe("otel batches", () => {
  it("names a mixed batch and drops the table when tables differ", async () => {
    const { tracer, spans } = memoryTracer();

    const betterSupabase = createSupabase(schema).use(
      otel({ tracer, metrics: false, database: "crm" }),
    );

    const db = betterSupabase.connect({
      name: "custom",
      execute: empty,
      batch: async (ops) => ops.map(() => ok({ rows: [], count: null })),
    });

    await db.$many([
      betterSupabase.spec.customers.list({ select: ["id"] }),
      betterSupabase.spec.organizations.count(),
    ]);

    const batch = spans.find((span) => span.name === "BATCH");

    expect(batch?.attributes).toMatchObject({
      "db.operation.name": "BATCH",
      "db.operation.batch.size": 2,
    });
    expect(batch?.attributes).not.toHaveProperty("db.collection.name");
    expect(batch?.attributes).not.toHaveProperty("db.namespace");
  });
});

describe("traceAuth and traceBlockEvents defaults", () => {
  it("adds the extra attributes and omits a missing user id", () => {
    const { tracer, spans } = memoryTracer();
    const events = new EventHub();

    const stop = traceAuth(
      { events },
      { tracer, attributes: { "service.namespace": "crm" } },
    );

    events.emit("auth", { source: "cookie", ok: false });
    events.emit("refresh", { ok: true, shared: false, durationMs: 5 });
    stop();

    expect(spans[0]?.attributes).toEqual({
      "service.namespace": "crm",
      "better_supabase.auth.source": "cookie",
    });
    expect(spans[0]?.status?.code).toBe(SpanStatusCode.ERROR);
    expect(spans[1]?.status).toBeUndefined();
    expect(spans[1]?.attributes).toMatchObject({
      "better_supabase.refresh.shared": false,
    });
  });

  it("works with the global tracer when none is given", () => {
    const events = new EventHub();
    const stopAuth = traceAuth({ events });
    const stopBlocks = traceBlockEvents({ events });

    expect(() => {
      events.emit("auth", { source: "none", ok: true });
    }).not.toThrow();
    stopAuth();
    stopBlocks();
  });
});

describe("tracedFetch inputs", () => {
  it("reads the headers of a Request and uses the global fetch by default", async () => {
    let seen: Headers | undefined;

    const traced = tracedFetch(async (_input, init) => {
      seen = new Headers(init?.headers);

      return new Response(null, { status: 204 });
    });

    await traced(
      new Request("http://localhost/rest/v1/x", {
        headers: { apikey: "from-request" },
      }),
    );
    expect(seen?.get("apikey")).toBe("from-request");
    await traced("http://localhost/rest/v1/x");
    expect([...(seen?.keys() ?? [])]).toEqual([]);
    expect(typeof tracedFetch()).toBe("function");
  });
});

describe("otel on a non-postgres executor", () => {
  it("uses the schema alone for function calls and batches, with the global meter", async () => {
    const { tracer, spans } = memoryTracer();
    const betterSupabase = createSupabase(schema).use(otel({ tracer }));

    const db = betterSupabase.connect({
      name: "custom",
      execute: empty,
      rpc: async () => ok(null),
      batch: async (ops) =>
        ops.map((_, index) =>
          index === 0
            ? ok({ rows: [{ id: "c1" }], count: null })
            : err(dbError("timeout", "slow")),
        ),
    });

    await db.$rpc("rs_workspace_summary", { p: null });
    await db.$many([
      betterSupabase.spec.customers.list({ select: ["id"] }),
      betterSupabase.spec.customers.list({ select: ["id"] }),
    ]);

    const rpc = spans.find((span) => span.name.startsWith("EXECUTE"));

    expect(rpc?.attributes["db.namespace"]).toBe("public");
    expect(rpc?.status).toBeUndefined();

    const batches = spans.filter((span) => span.name.startsWith("BATCH"));

    expect(batches.map((span) => span.attributes["db.namespace"])).toEqual([
      "public",
    ]);
  });

  it("sums returned rows over a batch of reads", async () => {
    const { tracer, spans } = memoryTracer();

    const betterSupabase = createSupabase(schema).use(
      otel({ tracer, metrics: false }),
    );

    const db = betterSupabase.connect({
      name: "custom",
      execute: empty,
      batch: async (ops) =>
        ops.map(() => ok({ rows: [{ id: "c1" }], count: null })),
    });

    await db.$many([
      betterSupabase.spec.customers.list({ select: ["id"] }),
      betterSupabase.spec.customers.list({ select: ["id"] }),
    ]);

    expect(
      spans.find((span) => span.name.startsWith("BATCH"))?.attributes[
        "db.response.returned_rows"
      ],
    ).toBe(2);
  });
});
