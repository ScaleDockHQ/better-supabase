import {
  type Context,
  context,
  type ContextManager,
  propagation,
  ROOT_CONTEXT,
  type TextMapPropagator,
  trace,
  TraceFlags,
} from "@opentelemetry/api";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { tracedFetch } from "../../src/otel/index.ts";

/** A synchronous context manager: enough for `fetch` calls made inside `context.with`. */
function stackContextManager(): ContextManager {
  const stack: Context[] = [];
  const manager: ContextManager = {
    active: () => stack.at(-1) ?? ROOT_CONTEXT,
    with: (ctx, fn, thisArg, ...args) => {
      stack.push(ctx);
      try {
        return fn.call(thisArg, ...args);
      } finally {
        stack.pop();
      }
    },
    bind: (_ctx, target) => target,
    enable: () => manager,
    disable: () => manager,
  };
  return manager;
}

/** The W3C Trace Context propagator: `traceparent` version 00 from the span context. */
const w3c: TextMapPropagator = {
  inject(ctx, carrier, setter) {
    const span = trace.getSpanContext(ctx);
    if (!span) return;
    const flags = `0${(span.traceFlags & TraceFlags.SAMPLED).toString(16)}`;
    setter.set(
      carrier,
      "traceparent",
      `00-${span.traceId}-${span.spanId}-${flags}`,
    );
    if (span.traceState)
      setter.set(carrier, "tracestate", span.traceState.serialize());
  },
  extract: (ctx) => ctx,
  fields: () => ["traceparent", "tracestate"],
};

const TRACEPARENT = /^00-(?!0{32})[0-9a-f]{32}-(?!0{16})[0-9a-f]{16}-0[01]$/;
const TRACE_ID = "0af7651916cd43dd8448eb211c80319c";
const SPAN_ID = "b7ad6b7169203331";

function inSpan<T>(fn: () => T, traceFlags = TraceFlags.SAMPLED): T {
  const span = trace.wrapSpanContext({
    traceId: TRACE_ID,
    spanId: SPAN_ID,
    traceFlags,
  });
  return context.with(trace.setSpan(context.active(), span), fn);
}

describe("W3C Trace Context", () => {
  beforeEach(() => {
    context.setGlobalContextManager(stackContextManager());
    propagation.setGlobalPropagator(w3c);
  });
  afterEach(() => {
    context.disable();
    propagation.disable();
  });

  const capture = () => {
    const seen: Headers[] = [];
    const fetch = tracedFetch(async (_input, init) => {
      seen.push(new Headers(init?.headers));
      return new Response(null, { status: 204 });
    });
    return { fetch, seen };
  };

  it("sends a version 00 traceparent of the active span (section 3.2)", async () => {
    const { fetch, seen } = capture();
    await inSpan(() => fetch("https://abc.supabase.co/rest/v1/customers"));
    expect(seen[0]!.get("traceparent")).toMatch(TRACEPARENT);
    expect(seen[0]!.get("traceparent")).toBe(`00-${TRACE_ID}-${SPAN_ID}-01`);
  });

  it("carries the sampled flag as is (section 3.2.2.5)", async () => {
    const { fetch, seen } = capture();
    await inSpan(
      () => fetch("https://abc.supabase.co/rest/v1/x"),
      TraceFlags.NONE,
    );
    expect(seen[0]!.get("traceparent")).toBe(`00-${TRACE_ID}-${SPAN_ID}-00`);
  });

  it("keeps the caller's headers, including those of a Request input", async () => {
    const { fetch, seen } = capture();
    await inSpan(() =>
      fetch("https://abc.supabase.co/rest/v1/x", { headers: { apikey: "k" } }),
    );
    await inSpan(() =>
      fetch(
        new Request("https://abc.supabase.co/rest/v1/x", {
          headers: { prefer: "count=exact" },
        }),
      ),
    );
    expect(seen[0]!.get("apikey")).toBe("k");
    expect(seen[1]!.get("prefer")).toBe("count=exact");
    expect(seen[1]!.get("traceparent")).toMatch(TRACEPARENT);
  });

  it("adds no traceparent outside a trace", async () => {
    const { fetch, seen } = capture();
    await fetch("https://abc.supabase.co/rest/v1/x");
    expect(seen[0]!.has("traceparent")).toBe(false);
  });
});
