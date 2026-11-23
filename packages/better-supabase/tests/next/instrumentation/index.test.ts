import { describe, expect, it, vi } from "vitest";

import type { BlockEvent } from "../../../src/core/block-events.ts";
import type { CloudEvent } from "../../../src/events/index.ts";

import { EventHub } from "../../../src/core/events.ts";
import { forwardBlockEvents } from "../../../src/events/index.ts";
import {
  createOnRequestError,
  requestEvents,
  warm,
} from "../../../src/next/instrumentation/index.ts";

describe("warm", () => {
  it("logs failed steps and never throws", async () => {
    const warn = vi.fn();

    const events = new EventHub({
      debug: () => undefined,
      info: () => undefined,
      warn,
      error: () => undefined,
    });

    const report = await warm({
      events,
      warm: async () => ({
        ms: 3,
        steps: [
          { name: "postgrest", ms: 1, ok: true },
          { name: "pool", ms: 2, ok: false, error: "refused" },
        ],
      }),
    });

    expect(report.ms).toBe(3);
    expect(warn).toHaveBeenCalledWith("bsb.warm pool failed", {
      error: "refused",
      ms: 2,
    });

    await expect(
      warm({ events, warm: () => Promise.reject(new Error("boom")) }),
    ).resolves.toEqual({ ms: 0, steps: [] });
  });
});

const request = {
  path: "/customers/42?token=secret#top",
  method: "GET",
  headers: { cookie: "sb=secret", "x-forwarded-for": "10.0.0.1" },
};

const context = {
  routerKind: "App Router",
  routePath: "/customers/[id]",
  routeType: "render",
  renderSource: "server-rendering",
  revalidateReason: undefined,
} as const;

function listen() {
  const events = new EventHub({
    debug: () => undefined,
    info: () => undefined,
    warn: () => undefined,
    error: () => undefined,
  });

  const seen: BlockEvent[] = [];
  events.on("block", (event) => seen.push(event));

  return { events, seen };
}

describe("createOnRequestError", () => {
  it("emits request.failed without the query string, headers or cookies", async () => {
    const { events, seen } = listen();
    const onRequestError = createOnRequestError({ events });

    await onRequestError(
      Object.assign(new TypeError("cannot read x"), { digest: "d123" }),
      request,
      context,
    );

    expect(seen).toHaveLength(1);
    expect(seen[0]?.type).toBe("request.failed");
    expect(seen[0]?.data).toEqual({
      name: "TypeError",
      message: "cannot read x",
      digest: "d123",
      path: "/customers/42",
      method: "GET",
      routerKind: "App Router",
      routePath: "/customers/[id]",
      routeType: "render",
      renderSource: "server-rendering",
    });
    expect(JSON.stringify(seen)).not.toContain("secret");
  });

  it("leaves the message out and cuts a long one", async () => {
    const { events, seen } = listen();

    await createOnRequestError({ events }, { message: false })(
      new Error("hidden"),
      request,
      context,
    );

    await createOnRequestError({ events }, { maxMessageLength: 4 })(
      new Error("abcdefgh"),
      request,
      context,
    );

    expect(seen[0]?.data).not.toHaveProperty("message");
    expect(seen[1]?.data).toMatchObject({ message: "abcd" });
  });

  it("reports a thrown string or object as an Error", async () => {
    const { events, seen } = listen();
    const onRequestError = createOnRequestError({ events });

    await onRequestError("plain", request, {
      ...context,
      revalidateReason: "stale",
    });
    await onRequestError({ odd: true }, request, context);

    expect(seen[0]?.data).toMatchObject({
      name: "Error",
      message: "plain",
      revalidateReason: "stale",
    });
    expect(seen[1]?.data).not.toHaveProperty("message");
  });

  it("sends the event to a sink and waits for it", async () => {
    const { events } = listen();
    const sent: CloudEvent[] = [];

    forwardBlockEvents(
      { events },
      {
        send: async (batch) => {
          await Promise.resolve();
          sent.push(...batch);
        },
      },
      { source: "https://crm.example.com" },
    );

    await createOnRequestError({ events })(new Error("boom"), request, context);

    expect(sent.map((event) => event.type)).toEqual([
      "dev.better-supabase.request.failed",
    ]);
  });

  it("stops waiting for a sink that never settles", async () => {
    const { events } = listen();

    forwardBlockEvents(
      { events },
      {
        send: () =>
          new Promise<void>(() => {
            // never settles
          }),
      },
      { source: "https://crm.example.com" },
    );

    const started = performance.now();

    await createOnRequestError({ events }, { settleMs: 20 })(
      new Error("boom"),
      request,
      context,
    );

    expect(performance.now() - started).toBeLessThan(1000);
  });

  it("never throws when a handler or the sink throws", async () => {
    const { events } = listen();
    events.on("block", () => {
      throw new Error("handler");
    });
    const error = vi.spyOn(events.logger, "error");

    await expect(
      createOnRequestError({ events })(new Error("boom"), request, context),
    ).resolves.toBeUndefined();
    expect(error.mock.calls.length).toBeGreaterThan(0);
  });

  it("logs and returns when emitting the event throws", async () => {
    const error = vi.fn();

    const events = {
      logger: { debug: vi.fn(), info: vi.fn(), warn: vi.fn(), error },
      emit: () => {
        throw new Error("emit");
      },
    } as unknown as EventHub;

    await expect(
      createOnRequestError({ events })(new Error("boom"), request, context),
    ).resolves.toBeUndefined();
    expect(error).toHaveBeenCalledWith(
      "request.failed bridge threw",
      expect.anything(),
    );
  });

  it("lists its event type", () => {
    expect(requestEvents.types).toEqual(["request.failed"]);
  });
});
