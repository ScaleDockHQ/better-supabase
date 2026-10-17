import { describe, expect, it, vi } from "vitest";

import {
  CAEP_EVENTS,
  createSsfReceiver,
  createSsfTransmitter,
  RISC_EVENTS,
  SSF_POLL,
  SSF_PUSH,
} from "../../../src/blocks/shared-signals/index.ts";
import { signingKey, store } from "./fixtures.ts";

const ISSUER = "https://tx.example";
const RECEIVER = { receiver: "rx" };
const STREAM = "/ssf/stream";

async function setup() {
  const t = store();
  const { signer, jwks } = await signingKey();
  const before = vi.fn();

  const transmitter = createSsfTransmitter({
    transport: t,
    issuer: ISSUER,
    jwksUri: `${ISSUER}/jwks`,
    signer,
    deliveryMethods: ["push", "poll"],
    authorize: (request) =>
      request.headers.get("authorization") === "Bearer rx" ? RECEIVER : null,
    hooks: { updateStream: { before } },
  });

  const handle = transmitter.handler();

  const http = (input: RequestInfo | URL, init?: RequestInit) => {
    const request = new Request(input, init);

    return request.url === `${ISSUER}/jwks`
      ? Promise.resolve(Response.json(jwks))
      : handle(request);
  };

  return { t, jwks, transmitter, handle, http, before };
}

const call = (path: string, method = "GET", body?: unknown) =>
  new Request(`${ISSUER}${path}`, {
    method,
    headers: { authorization: "Bearer rx", "content-type": "application/json" },
    ...(body === undefined
      ? {}
      : { body: typeof body === "string" ? body : JSON.stringify(body) }),
  });

const pollStream = (
  transmitter: Awaited<ReturnType<typeof setup>>["transmitter"],
) =>
  transmitter
    .createStream({
      receiver: RECEIVER,
      method: "poll",
      eventsRequested: [CAEP_EVENTS.sessionRevoked],
      description: "first",
    })
    .orThrow();

const pushStream = (
  transmitter: Awaited<ReturnType<typeof setup>>["transmitter"],
) =>
  transmitter
    .createStream({
      receiver: RECEIVER,
      method: "push",
      eventsRequested: [CAEP_EVENTS.sessionRevoked],
      endpointUrl: "https://rx.example/ssf",
    })
    .orThrow();

describe("shared-signals transmitter routes", () => {
  it("updates a stream with PATCH and replaces it with PUT", async () => {
    const { handle, transmitter, before } = await setup();
    const stream = await pollStream(transmitter);

    const patched = await handle(
      call(STREAM, "PATCH", {
        stream_id: stream.id,
        events_requested: [RISC_EVENTS.accountDisabled],
      }),
    );

    expect(await patched.json()).toMatchObject({
      description: "first",
      events_delivered: [RISC_EVENTS.accountDisabled],
    });

    const replaced = await handle(
      call(STREAM, "PUT", {
        stream_id: stream.id,
        delivery: { method: SSF_POLL },
      }),
    );

    const body = await replaced.json();
    expect(body).toMatchObject({ events_requested: [], events_delivered: [] });
    expect(body).not.toHaveProperty("description");
    expect(before).toHaveBeenCalledTimes(2);
  });

  it("moves a push stream's endpoint and refuses a method change", async () => {
    const { handle, transmitter } = await setup();
    const stream = await pushStream(transmitter);

    const moved = await handle(
      call(STREAM, "PATCH", {
        stream_id: stream.id,
        delivery: { endpoint_url: "https://rx.example/new" },
        description: "moved",
      }),
    );

    expect(await moved.json()).toMatchObject({
      delivery: { method: SSF_PUSH, endpoint_url: "https://rx.example/new" },
      description: "moved",
    });

    const changed = await handle(
      call(STREAM, "PATCH", {
        stream_id: stream.id,
        delivery: { method: SSF_POLL },
      }),
    );

    expect(changed.status).toBe(400);
  });

  it("answers 400 to bad bodies and 404 to unknown streams", async () => {
    const { handle } = await setup();

    const statuses = await Promise.all(
      [
        call(STREAM, "PATCH"),
        call(STREAM, "PATCH", { stream_id: "" }),
        call(STREAM, "PATCH", { stream_id: "not-a-uuid" }),
        call(STREAM, "POST", "{not json"),
        call(STREAM, "POST", "[]"),
        call(STREAM, "POST", { delivery: { method: "urn:other" } }),
        call(`${STREAM}?stream_id=${crypto.randomUUID()}`, "DELETE"),
        call("/ssf/status", "POST", {
          stream_id: crypto.randomUUID(),
          status: "paused",
        }),
        call("/ssf/unknown"),
        call("/elsewhere"),
      ].map(async (request) => (await handle(request)).status),
    );

    expect(statuses).toEqual([
      400, 400, 404, 400, 400, 400, 404, 404, 404, 404,
    ]);
  });

  it("answers 405 with Allow to unsupported methods", async () => {
    const { handle } = await setup();

    const cases: [Request, string][] = [
      [call(STREAM, "OPTIONS"), "GET, POST, PATCH, PUT, DELETE"],
      [call("/ssf/status", "PUT"), "GET, POST"],
      [call("/ssf/verify", "GET"), "POST"],
      [call(`/ssf/poll/${crypto.randomUUID()}`, "GET"), "POST"],
      [
        new Request(`${ISSUER}/.well-known/ssf-configuration`, {
          method: "POST",
        }),
        "GET",
      ],
    ];

    for (const [request, allow] of cases) {
      const response = await handle(request);
      expect(response.status).toBe(405);
      expect(response.headers.get("allow")).toBe(allow);
      expect(response.headers.get("cache-control")).toBeNull();
    }
  });

  it("reads and sets the status with a reason, and refuses an unknown status", async () => {
    const { handle, transmitter } = await setup();
    const stream = await pollStream(transmitter);

    const set = await handle(
      call("/ssf/status", "POST", {
        stream_id: stream.id,
        status: "paused",
        reason: "maintenance",
      }),
    );

    expect(await set.json()).toEqual({
      stream_id: stream.id,
      status: "paused",
      reason: "maintenance",
    });
    const read = await handle(call(`/ssf/status?stream_id=${stream.id}`));
    expect(await read.json()).toEqual({
      stream_id: stream.id,
      status: "paused",
      reason: "maintenance",
    });

    const bad = await handle(
      call("/ssf/status", "POST", { stream_id: stream.id, status: "gone" }),
    );

    expect(bad.status).toBe(400);
    const missing = await handle(call("/ssf/status", "POST", {}));
    expect(missing.status).toBe(400);
  });

  it("polls only poll streams and passes acks and set errors", async () => {
    const { handle, transmitter, t } = await setup();
    const push = await pushStream(transmitter);
    expect((await handle(call(`/ssf/poll/${push.id}`, "POST"))).status).toBe(
      404,
    );
    const stream = await pollStream(transmitter);

    const polled = await handle(
      call(`/ssf/poll/${stream.id}`, "POST", {
        maxEvents: 5,
        ack: ["a"],
        setErrs: { b: { err: "invalid_key", description: "x" }, c: "bad" },
      }),
    );

    expect(await polled.json()).toEqual({ sets: {}, moreAvailable: false });
    expect(t.calls.find(([fn]) => fn === "poll_ssf_events")?.[1]).toEqual({
      stream_id: stream.id,
      max_events: 5,
      ack: ["a"],
      errors: { b: { err: "invalid_key" } },
    });
    const empty = await handle(call(`/ssf/poll/${stream.id}`, "POST"));
    expect(empty.status).toBe(200);
  });

  it("deletes a stream with DELETE", async () => {
    const { handle, transmitter } = await setup();
    const stream = await pollStream(transmitter);

    const deleted = await handle(
      call(`${STREAM}?stream_id=${stream.id}`, "DELETE"),
    );

    expect(deleted.status).toBe(204);
    const read = await handle(call(`${STREAM}?stream_id=${stream.id}`));
    expect(read.status).toBe(404);
  });
});

describe("shared-signals transmitter methods", () => {
  it("refuses unsupported methods, http endpoints and headers without Vault", async () => {
    const { t } = await setup();
    const { signer } = await signingKey();

    const pollOnly = createSsfTransmitter({
      transport: t,
      issuer: ISSUER,
      jwksUri: `${ISSUER}/jwks`,
      signer,
      deliveryMethods: ["poll"],
      authorize: () => RECEIVER,
    });

    const hints = await Promise.all(
      [
        pollOnly.createStream({
          receiver: RECEIVER,
          method: "push",
          eventsRequested: [],
          endpointUrl: "https://rx.example",
        }),
        pollOnly.createStream({
          receiver: RECEIVER,
          method: "poll",
          eventsRequested: [],
          authorizationHeader: "ignored for poll",
        }),
      ].map(async (result) => {
        const settled = await result;

        return settled.ok ? "ok" : settled.error.hint;
      }),
    );

    expect(hints).toEqual(["SSF_REQUEST_INVALID", "ok"]);
    const { transmitter } = await setup();

    const header = await transmitter.createStream({
      receiver: RECEIVER,
      method: "push",
      eventsRequested: [],
      endpointUrl: "https://rx.example",
      authorizationHeader: "Bearer x",
    });

    expect(!header.ok && header.error.message).toMatch(/authorization_header/);
    expect(pollOnly.metadata()["delivery_methods_supported"]).toEqual([
      SSF_POLL,
    ]);
  });

  it("answers unknown streams with null, false or not_found", async () => {
    const { transmitter } = await setup();
    const id = crypto.randomUUID();
    expect(await transmitter.updateStream(id, {}).orThrow()).toBeNull();
    expect(await transmitter.deleteStream(id).orThrow()).toBe(false);
    const status = await transmitter.setStatus(id, "paused");
    expect(!status.ok && status.error.hint).toBe("SSF_STREAM_NOT_FOUND");
    const verify = await transmitter.verify(id);
    expect(!verify.ok && verify.error.hint).toBe("SSF_STREAM_NOT_FOUND");
  });

  it("purges with a retention in seconds", async () => {
    const { transmitter, t } = await setup();
    expect(
      await transmitter.purge(Temporal.Duration.from({ hours: 1 })).orThrow(),
    ).toBe(0);
    expect(await transmitter.purge().orThrow()).toBe(0);
    expect(
      t.calls.filter(([fn]) => fn === "purge_shared_signals").map(([, a]) => a),
    ).toEqual([{ older_than: "3600 seconds" }, { older_than: null }]);
  });
});

describe("shared-signals receiver edges", () => {
  const set = async () => {
    const { transmitter, t, http, jwks } = await setup();
    await pushStream(transmitter);
    await transmitter
      .emit({
        subject: { format: "opaque", id: "u1" },
        event: { type: CAEP_EVENTS.sessionRevoked, claims: {} },
      })
      .orThrow();

    return { token: t.dispatched[0]!.set, t, http, jwks, transmitter };
  };

  it("checks the push request's method, content type and size", async () => {
    const { t } = await set();

    const push = createSsfReceiver({
      transport: t,
      issuer: ISSUER,
      audience: "rx",
      jwks: { keys: [] },
      maxBodyBytes: 8,
    }).pushHandler();

    const post = (
      body: string,
      type = "application/secevent+jwt; charset=utf-8",
    ) =>
      push(
        new Request("https://rx.example/ssf", {
          method: "POST",
          headers: { "content-type": type },
          body,
        }),
      );

    expect((await push(new Request("https://rx.example/ssf"))).status).toBe(
      405,
    );
    expect(await (await post("x", "application/json")).json()).toMatchObject({
      err: "invalid_request",
    });
    expect(await (await post("x".repeat(64))).json()).toMatchObject({
      err: "invalid_request",
      description: "The SET is too large",
    });
    expect(await (await post("a.b.c")).json()).toMatchObject({
      err: "invalid_request",
    });
  });

  it("takes keys from a function and fails with invalid_key when none verifies", async () => {
    const { token, t, jwks } = await set();
    const keys = vi.fn(() => Promise.resolve(jwks));

    const receiver = createSsfReceiver({
      transport: t,
      issuer: ISSUER,
      audience: "rx",
      jwks: keys,
    });

    expect(await receiver.receive(token)).toMatchObject({ ok: true });

    const empty = createSsfReceiver({
      transport: t,
      issuer: ISSUER,
      audience: "rx",
      jwks: { keys: [] },
    });

    expect(await empty.receive(token)).toMatchObject({
      ok: false,
      err: "invalid_key",
    });
  });

  it("reports discovery failures", async () => {
    const { t } = await set();

    const discover = (fetch: typeof globalThis.fetch) =>
      createSsfReceiver({ transport: t, issuer: ISSUER, audience: "rx", fetch })
        .discover()
        .then((result) => (result.ok ? "ok" : result.error.kind));

    expect(await discover(() => Promise.reject(new Error("offline")))).toBe(
      "network",
    );
    expect(
      await discover(() =>
        Promise.resolve(new Response(null, { status: 404 })),
      ),
    ).toBe("not_found");
    expect(
      await discover(() =>
        Promise.resolve(new Response(null, { status: 503 })),
      ),
    ).toBe("unexpected");
    expect(await discover(() => Promise.resolve(new Response("<html>")))).toBe(
      "unexpected",
    );

    const noJwks = createSsfReceiver({
      transport: t,
      issuer: ISSUER,
      audience: "rx",
      fetch: () => Promise.resolve(Response.json({ issuer: ISSUER })),
    });

    const { token } = await set();
    expect(await noJwks.receive(token)).toMatchObject({
      ok: false,
      err: "invalid_key",
    });
  });

  it("caches the metadata and keys between SETs", async () => {
    const { token, http, t } = await set();
    const fetch = vi.fn(http);

    const receiver = createSsfReceiver({
      transport: t,
      issuer: ISSUER,
      audience: "rx",
      fetch,
    });

    await receiver.receive(token);
    await receiver.receive(token);
    expect(fetch).toHaveBeenCalledTimes(2);
  });

  it("reports rejected SETs back to the transmitter when polling", async () => {
    const t = store();
    const bodies: unknown[] = [];

    const responses = [
      { sets: { j1: "a.b.c", j2: 7 }, moreAvailable: false },
      {},
    ];

    const receiver = createSsfReceiver({
      transport: t,
      issuer: ISSUER,
      audience: "rx",
      jwks: { keys: [] },
      fetch: (_url, init) => {
        bodies.push(JSON.parse(String(init?.body)));

        return Promise.resolve(Response.json(responses.shift() ?? {}));
      },
    });

    expect(
      await receiver
        .poll({ endpoint: `${ISSUER}/ssf/poll/x`, authorization: "Bearer rx" })
        .orThrow(),
    ).toEqual({ received: 0, rejected: 1, failed: 0, moreAvailable: false });
    expect(bodies[1]).toMatchObject({
      maxEvents: 0,
      ack: [],
      setErrs: { j1: { err: "invalid_request" } },
    });

    const failing = createSsfReceiver({
      transport: t,
      issuer: ISSUER,
      audience: "rx",
      fetch: () => Promise.resolve(new Response(null, { status: 500 })),
    });

    const result = await failing.poll({
      endpoint: `${ISSUER}/ssf/poll/x`,
      authorization: "Bearer rx",
    });

    expect(!result.ok && result.error.kind).toBe("unexpected");
  });

  it("reads, sets and verifies streams through the management client", async () => {
    const { http, t, transmitter } = await set();
    const stream = await pollStream(transmitter);

    const client = createSsfReceiver({
      transport: t,
      issuer: ISSUER,
      audience: "rx",
      fetch: http,
    }).streams("Bearer rx");

    expect(await client.read(stream.id).orThrow()).toMatchObject({
      stream_id: stream.id,
    });
    expect(
      await client.setStatus(stream.id, "disabled", "done").orThrow(),
    ).toEqual({ stream_id: stream.id, status: "disabled", reason: "done" });
    const unknown = await client.verify(crypto.randomUUID());
    expect(!unknown.ok && unknown.error.kind).toBe("unexpected");

    const offline = createSsfReceiver({
      transport: t,
      issuer: ISSUER,
      audience: "rx",
      fetch: (input, init) =>
        String(input).includes("/verify")
          ? Promise.reject(new Error("offline"))
          : http(input, init),
    }).streams("Bearer rx");

    const down = await offline.verify(stream.id);
    expect(!down.ok && down.error.kind).toBe("network");

    const bare = createSsfReceiver({
      transport: t,
      issuer: ISSUER,
      audience: "rx",
      fetch: () => Promise.resolve(Response.json({ issuer: ISSUER })),
    }).streams("Bearer rx");

    const missing = await bare.status(stream.id);
    expect(!missing.ok && missing.error.kind).toBe("unsupported");
  });

  it("purges replay entries with a retention", async () => {
    const t = store();

    const receiver = createSsfReceiver({
      transport: t,
      issuer: ISSUER,
      audience: "rx",
      jwks: { keys: [] },
    });

    await receiver.purge(Temporal.Duration.from({ minutes: 1 })).orThrow();
    await receiver.purge().orThrow();
    expect(
      t.calls.filter(([fn]) => fn === "purge_shared_signals").map(([, a]) => a),
    ).toEqual([{ older_than: "60 seconds" }, { older_than: null }]);
  });
});
