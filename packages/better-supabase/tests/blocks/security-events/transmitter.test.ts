import { describe, expect, it, vi } from "vitest";

import type { SetSigner } from "../../../src/blocks/security-events/set.ts";
import type { CredentialRef } from "../../../src/credentials/provider.ts";

import {
  CAEP_EVENTS,
  createSsfTransmitter,
  SSF_POLL,
  SSF_PUSH,
} from "../../../src/blocks/security-events/index.ts";
import { dbError } from "../../../src/core/errors.ts";
import { AsyncResult } from "../../../src/core/result.ts";
import { signingKey, store } from "./fixtures.ts";

const ISSUER = "https://tx.example";
const RECEIVER = { receiver: "rx" };
const STREAM = "/ssf/stream";

type Options = Parameters<typeof createSsfTransmitter>[0];

/** The in-memory module, with calls that can be forced to throw or answer. */
async function rig(extra: Partial<Options> = {}) {
  const t = store();
  const { signer } = await signingKey();
  const failing = new Set<string>();
  const forced = new Map<string, unknown>();
  const control = { signerFails: false };

  const guarded: SetSigner = {
    signJwt: (claims, header) =>
      control.signerFails
        ? AsyncResult.err(dbError("unexpected", "signer down"))
        : signer.signJwt(claims, header),
  };

  const transport = {
    call: (
      schema: string,
      fn: string,
      args: Readonly<Record<string, unknown>>,
    ) => {
      if (failing.has(fn)) {
        return Promise.reject(new Error(`${fn} failed`));
      }

      if (forced.has(fn)) {
        return Promise.resolve(forced.get(fn));
      }

      return t.call(schema, fn, { ...args });
    },
  };

  const transmitter = createSsfTransmitter({
    transport,
    issuer: ISSUER,
    jwksUri: `${ISSUER}/jwks`,
    signer: guarded,
    authorize: (request) =>
      request.headers.get("authorization") === "Bearer rx" ? RECEIVER : null,
    ...extra,
  });

  return {
    t,
    failing,
    forced,
    control,
    transmitter,
    handle: transmitter.handler(),
  };
}

type Rig = Awaited<ReturnType<typeof rig>>;

const call = (path: string, method = "GET", body?: unknown) =>
  new Request(`${ISSUER}${path}`, {
    method,
    headers: { authorization: "Bearer rx", "content-type": "application/json" },
    ...(body === undefined
      ? {}
      : { body: typeof body === "string" ? body : JSON.stringify(body) }),
  });

const create = (r: Rig, method: "push" | "poll") =>
  r.transmitter
    .createStream({
      receiver: RECEIVER,
      method,
      eventsRequested: [CAEP_EVENTS.sessionRevoked],
      ...(method === "push" ? { endpointUrl: "https://rx.example/ssf" } : {}),
    })
    .orThrow();

const payloadOf = (token: string): Record<string, unknown> =>
  // SAFETY: the SETs minted in this file carry a JSON object payload.
  JSON.parse(
    atob(token.split(".")[1]!.replaceAll("-", "+").replaceAll("_", "/")),
  ) as Record<string, unknown>;

describe("transmitter methods", () => {
  it("throws on a stream row with an unknown status", async () => {
    const r = await rig();
    const stream = await create(r, "poll");
    r.t.streams[0]!.status = "weird";

    const result = await r.transmitter.stream(stream.id);

    expect(!result.ok && result.error.message).toMatch(
      /Unknown stream status weird/,
    );
  });

  it("keeps the tenant and a list of audiences on the stream and its credential", async () => {
    const set = vi.fn(() => AsyncResult.ok<void>(undefined));

    const revoke = vi.fn((_ref: CredentialRef, _options: unknown) =>
      AsyncResult.ok(true),
    );

    const r = await rig({ credentials: { set, revoke } });

    const stream = await r.transmitter
      .createStream({
        receiver: { receiver: "rx", tenant: "t1", audience: ["a", "b"] },
        method: "push",
        eventsRequested: [CAEP_EVENTS.sessionRevoked],
        endpointUrl: "https://rx.example/ssf",
        authorizationHeader: "Bearer secret",
      })
      .orThrow();

    expect(stream).toMatchObject({ tenant: "t1", audience: ["a", "b"] });
    expect(set).toHaveBeenCalledWith(
      expect.objectContaining({ tenant: "t1", secret: `ssf/${stream.id}` }),
      "Bearer secret",
    );

    expect(await r.transmitter.deleteStream(stream.id).orThrow()).toBe(true);
    expect(revoke).toHaveBeenCalledWith(
      expect.objectContaining({ tenant: "t1" }),
      { subject: { type: "app" } },
    );
  });

  it("revokes an app-wide credential without a tenant and skips revoke for poll streams", async () => {
    const set = vi.fn(() => AsyncResult.ok<void>(undefined));

    const revoke = vi.fn((_ref: CredentialRef, _options: unknown) =>
      AsyncResult.ok(true),
    );

    const r = await rig({ credentials: { set, revoke } });

    const push = await r.transmitter
      .createStream({
        receiver: RECEIVER,
        method: "push",
        eventsRequested: [],
        endpointUrl: "https://rx.example/ssf",
        authorizationHeader: "Bearer x",
      })
      .orThrow();

    await r.transmitter.deleteStream(push.id).orThrow();
    expect(revoke.mock.calls[0]![0]).not.toHaveProperty("tenant");

    const poll = await create(r, "poll");
    await r.transmitter.deleteStream(poll.id).orThrow();
    expect(revoke).toHaveBeenCalledOnce();
  });

  it("returns the credential error when Vault refuses the header", async () => {
    const set = vi.fn(() =>
      AsyncResult.err<void>(dbError("unexpected", "vault down")),
    );

    const r = await rig({
      credentials: { set, revoke: () => AsyncResult.ok(true) },
    });

    const result = await r.transmitter.createStream({
      receiver: RECEIVER,
      method: "push",
      eventsRequested: [],
      endpointUrl: "https://rx.example/ssf",
      authorizationHeader: "Bearer x",
    });

    expect(!result.ok && result.error.message).toBe("vault down");
    expect(r.t.streams).toHaveLength(0);
  });

  it("refuses a push stream without an endpoint", async () => {
    const r = await rig();

    const result = await r.transmitter.createStream({
      receiver: RECEIVER,
      method: "push",
      eventsRequested: [],
    });

    expect(!result.ok && result.error.hint).toBe(
      "SECURITY_EVENT_REQUEST_INVALID",
    );
  });

  it("sends stream-updated before pausing and after enabling, and reports failures", async () => {
    const r = await rig();
    const stream = await create(r, "poll");

    r.control.signerFails = true;

    const first = await r.transmitter.setStatus({
      id: stream.id,
      status: "paused",
      reason: "maintenance",
    });

    expect(!first.ok && first.error.message).toBe("signer down");
    expect(r.t.streams[0]!.status).toBe("enabled");

    r.control.signerFails = false;
    expect(
      await r.transmitter
        .setStatus({ id: stream.id, status: "paused", reason: "maintenance" })
        .orThrow(),
    ).toBe("enabled");
    expect(r.t.streams[0]).toMatchObject({
      status: "paused",
      reason: "maintenance",
    });
    expect(r.t.queued).toHaveLength(1);
    const events = payloadOf(r.t.queued[0]!.token)["events"];
    expect(JSON.stringify(events)).toContain('"status":"paused"');
    expect(JSON.stringify(events)).toContain('"reason":"maintenance"');

    r.control.signerFails = true;

    const resume = await r.transmitter.setStatus({
      id: stream.id,
      status: "enabled",
    });

    expect(!resume.ok && resume.error.message).toBe("signer down");

    r.control.signerFails = false;
    r.t.streams[0]!.status = "paused";
    expect(
      await r.transmitter
        .setStatus({ id: stream.id, status: "enabled" })
        .orThrow(),
    ).toBe("paused");
    expect(r.t.queued).toHaveLength(2);

    r.failing.add("set_ssf_stream_status");

    const broken = await r.transmitter.setStatus({
      id: stream.id,
      status: "disabled",
    });

    expect(broken.ok).toBe(false);
  });

  it("does not send stream-updated again when the status stays enabled", async () => {
    const r = await rig();
    const stream = await create(r, "poll");

    await r.transmitter
      .setStatus({ id: stream.id, status: "enabled" })
      .orThrow();
    expect(r.t.queued).toHaveLength(0);
  });

  it("carries the state of a verification event", async () => {
    const r = await rig();
    const stream = await create(r, "poll");

    await r.transmitter.verify({ id: stream.id, state: "abc" }).orThrow();
    await r.transmitter.verify({ id: stream.id }).orThrow();

    const claims = r.t.queued.map((q) =>
      JSON.stringify(payloadOf(q.token)["events"]),
    );

    expect(claims[0]).toContain('"state":"abc"');
    expect(claims[1]).not.toContain("state");
  });

  it("emits with a txn and a tenant, and counts only known outcomes", async () => {
    const r = await rig();
    await create(r, "push");
    await create(r, "poll");

    const result = await r.transmitter
      .emit({
        subject: { format: "opaque", id: "u1" },
        event: { type: CAEP_EVENTS.sessionRevoked, claims: {} },
        tenant: "t1",
        txn: "txn-1",
      })
      .orThrow();

    expect(result).toEqual({ streams: 2, dispatched: 1, queued: 1, held: 0 });
    expect(payloadOf(r.t.dispatched[0]!.set)["txn"]).toBe("txn-1");
    expect(
      r.t.calls.find(([fn]) => fn === "ssf_streams_for_event")![1],
    ).toMatchObject({ tenant: "t1" });

    r.forced.set("queue_ssf_set", "dropped");
    expect(
      await r.transmitter
        .emit({
          subject: { format: "opaque", id: "u1" },
          event: { type: CAEP_EVENTS.sessionRevoked, claims: {} },
        })
        .orThrow(),
    ).toEqual({ streams: 2, dispatched: 0, queued: 0, held: 0 });
  });

  it("stops emitting at the first failed stream", async () => {
    const r = await rig();
    await create(r, "poll");
    r.control.signerFails = true;

    const result = await r.transmitter.emit({
      subject: { format: "opaque", id: "u1" },
      event: { type: CAEP_EVENTS.sessionRevoked, claims: {} },
    });

    expect(!result.ok && result.error.message).toBe("signer down");
  });

  it("polls with defaults and tolerates an empty answer", async () => {
    const r = await rig();
    const stream = await create(r, "poll");

    r.forced.set("poll_ssf_events", { sets: "nope" });
    expect(
      await r.transmitter.poll({ id: stream.id, request: {} }).orThrow(),
    ).toEqual({ sets: {}, moreAvailable: false });

    r.forced.delete("poll_ssf_events");
    await r.transmitter.poll({ id: stream.id, request: {} }).orThrow();

    expect(r.t.calls.at(-1)![1]).toMatchObject({
      max_events: null,
      ack: [],
      errors: {},
    });
  });

  it("updates only the fields it is given", async () => {
    const r = await rig();
    const stream = await create(r, "push");

    await r.transmitter
      .updateStream({
        id: stream.id,
        input: { description: "d", endpointUrl: "https://rx.example/b" },
      })
      .orThrow();

    expect(r.t.calls.at(-1)![1]).toEqual({
      id: stream.id,
      patch: { description: "d", endpointUrl: "https://rx.example/b" },
    });

    r.forced.set("update_ssf_stream", null);
    expect(
      await r.transmitter.updateStream({ id: stream.id, input: {} }).orThrow(),
    ).toBeNull();
  });

  it("reports an error from the delete call and keeps the credential", async () => {
    const revoke = vi.fn((_ref: CredentialRef, _options: unknown) =>
      AsyncResult.ok(true),
    );

    const r = await rig({
      credentials: { set: () => AsyncResult.ok<void>(undefined), revoke },
    });

    const stream = await create(r, "push");
    r.failing.add("delete_ssf_stream");

    const result = await r.transmitter.deleteStream(stream.id);
    expect(result.ok).toBe(false);
    expect(revoke).not.toHaveBeenCalled();
  });

  it("passes the logger to the hooks", async () => {
    const logger = {
      debug: vi.fn(),
      info: vi.fn(),
      warn: vi.fn(),
      error: vi.fn(),
    };

    const after = vi.fn(() => {
      throw new Error("after failed");
    });

    const r = await rig({ logger, hooks: { purge: { after } } });
    await r.transmitter.purge().orThrow();

    expect(after).toHaveBeenCalledOnce();
    expect(logger.error).toHaveBeenCalledExactlyOnceWith(
      "security-events.purge after hook threw",
      { cause: new Error("after failed") },
    );
  });

  it("answers the default and the custom metadata", async () => {
    const r = await rig({
      eventsSupported: [CAEP_EVENTS.sessionRevoked],
      authorizationSchemes: [{ spec_urn: "urn:custom" }],
      basePath: "/x/",
    });

    expect(r.transmitter.metadata()).toMatchObject({
      configuration_endpoint: `${ISSUER}/x/stream`,
      authorization_schemes: [{ spec_urn: "urn:custom" }],
    });
  });
});

describe("transmitter routes", () => {
  it("lists streams with one or many audiences and without a description", async () => {
    const r = await rig();
    await r.transmitter
      .createStream({
        receiver: { ...RECEIVER, audience: ["a", "b"] },
        method: "poll",
        eventsRequested: [],
      })
      .orThrow();

    await create(r, "poll");

    const list = await (await r.handle(call(STREAM))).json();
    expect(list).toHaveLength(2);
    expect(list[0]).toMatchObject({ aud: ["a", "b"] });
    expect(list[0]).not.toHaveProperty("description");
    expect(list[1]).toMatchObject({ aud: "rx" });
    expect(list[1].delivery.endpoint_url).toMatch(/\/ssf\/poll\//);

    r.failing.add("ssf_streams");
    expect((await r.handle(call(STREAM))).status).toBeGreaterThanOrEqual(400);
  });

  it("validates the stream id on read, delete and lookups", async () => {
    const r = await rig();
    const stream = await create(r, "poll");

    expect((await r.handle(call(`${STREAM}?stream_id=`))).status).toBe(400);
    expect((await r.handle(call(`${STREAM}?stream_id=nope`))).status).toBe(404);
    expect(
      (await r.handle(call(`${STREAM}?stream_id=${stream.id}`))).status,
    ).toBe(200);

    r.failing.add("ssf_stream");
    expect(
      (await r.handle(call(`${STREAM}?stream_id=${stream.id}`))).status,
    ).toBeGreaterThanOrEqual(500);
    expect(
      (await r.handle(call(`${STREAM}?stream_id=${stream.id}`, "DELETE")))
        .status,
    ).toBeGreaterThanOrEqual(500);
  });

  it("creates a stream from a POST and refuses bad ones", async () => {
    const r = await rig();

    const created = await r.handle(
      call(STREAM, "POST", {
        delivery: { method: SSF_PUSH, endpoint_url: "https://rx.example/ssf" },
        events_requested: [CAEP_EVENTS.sessionRevoked],
        description: "from route",
      }),
    );

    expect(created.status).toBe(201);
    expect(await created.json()).toMatchObject({ description: "from route" });

    const poll = await r.handle(
      call(STREAM, "POST", { delivery: { method: SSF_POLL } }),
    );

    expect(poll.status).toBe(201);

    for (const body of [
      "not json",
      "",
      { delivery: { method: "urn:other" } },
      { events_requested: "x" },
    ]) {
      expect((await r.handle(call(STREAM, "POST", body))).status).toBe(400);
    }

    const insecure = await r.handle(
      call(STREAM, "POST", {
        delivery: { method: SSF_PUSH, endpoint_url: "http://rx.example" },
      }),
    );

    expect(insecure.status).toBe(400);

    const header = await r.handle(
      call(STREAM, "POST", {
        delivery: {
          method: SSF_PUSH,
          endpoint_url: "https://rx.example",
          authorization_header: "Bearer x",
        },
      }),
    );

    expect(header.status).toBe(400);
  });

  it("refuses an update without a body or for another receiver's stream", async () => {
    const r = await rig();
    const stream = await create(r, "push");
    await create(r, "poll");

    expect((await r.handle(call(STREAM, "PATCH", "{"))).status).toBe(400);
    expect(
      (
        await r.handle(
          call(STREAM, "PATCH", { stream_id: crypto.randomUUID() }),
        )
      ).status,
    ).toBe(404);
    expect((await r.handle(call(STREAM, "PATCH", {}))).status).toBe(400);

    r.t.streams[0]!.receiver = "other";
    expect(
      (await r.handle(call(STREAM, "PATCH", { stream_id: stream.id }))).status,
    ).toBe(404);
    expect(
      (await r.handle(call(`${STREAM}?stream_id=${stream.id}`, "DELETE")))
        .status,
    ).toBe(404);
  });

  it("answers an update that the module rejects or loses", async () => {
    const r = await rig();
    const stream = await create(r, "poll");

    r.forced.set("update_ssf_stream", null);
    expect(
      (await r.handle(call(STREAM, "PATCH", { stream_id: stream.id }))).status,
    ).toBe(404);

    r.forced.delete("update_ssf_stream");
    r.failing.add("update_ssf_stream");
    expect(
      (
        await r.handle(
          call(STREAM, "PATCH", { stream_id: stream.id, description: "x" }),
        )
      ).status,
    ).toBeGreaterThanOrEqual(500);
  });

  it("ignores an endpoint for a poll stream and a non-string description", async () => {
    const r = await rig();
    const stream = await create(r, "poll");

    const response = await r.handle(
      call(STREAM, "PATCH", {
        stream_id: stream.id,
        delivery: { endpoint_url: "https://rx.example/x" },
        description: 5,
        events_requested: [CAEP_EVENTS.sessionRevoked],
      }),
    );

    expect(response.status).toBe(200);
    expect(r.t.calls.at(-1)![1]).toMatchObject({
      patch: { eventsRequested: [CAEP_EVENTS.sessionRevoked] },
    });
  });

  it("deletes a stream, fails the delete and rejects other methods", async () => {
    const r = await rig();
    const stream = await create(r, "poll");

    r.failing.add("delete_ssf_stream");
    expect(
      (await r.handle(call(`${STREAM}?stream_id=${stream.id}`, "DELETE")))
        .status,
    ).toBeGreaterThanOrEqual(500);

    r.failing.delete("delete_ssf_stream");
    expect(
      (await r.handle(call(`${STREAM}?stream_id=${stream.id}`, "DELETE")))
        .status,
    ).toBe(204);

    const other = await r.handle(call(STREAM, "OPTIONS"));
    expect(other.status).toBe(405);
    expect(other.headers.get("allow")).toBe("GET, POST, PATCH, PUT, DELETE");
  });

  it("reads and changes the status over HTTP", async () => {
    const r = await rig();
    const stream = await create(r, "poll");
    const url = "/ssf/status";

    expect(
      await (await r.handle(call(`${url}?stream_id=${stream.id}`))).json(),
    ).toEqual({ stream_id: stream.id, status: "enabled" });

    const paused = await r.handle(
      call(url, "POST", {
        stream_id: stream.id,
        status: "paused",
        reason: "audit",
      }),
    );

    expect(await paused.json()).toEqual({
      stream_id: stream.id,
      status: "paused",
      reason: "audit",
    });

    expect(
      await (await r.handle(call(`${url}?stream_id=${stream.id}`))).json(),
    ).toEqual({ stream_id: stream.id, status: "paused", reason: "audit" });

    const resumed = await r.handle(
      call(url, "POST", { stream_id: stream.id, status: "enabled" }),
    );

    expect(await resumed.json()).toEqual({
      stream_id: stream.id,
      status: "enabled",
    });

    expect((await r.handle(call(`${url}?stream_id=nope`))).status).toBe(404);
    expect((await r.handle(call(url, "DELETE"))).status).toBe(405);
    expect((await r.handle(call(url, "POST", { stream_id: 5 }))).status).toBe(
      400,
    );
    expect(
      (await r.handle(call(url, "POST", { stream_id: stream.id, status: "x" })))
        .status,
    ).toBe(400);

    r.control.signerFails = true;
    expect(
      (
        await r.handle(
          call(url, "POST", { stream_id: stream.id, status: "paused" }),
        )
      ).status,
    ).toBeGreaterThanOrEqual(500);
  });

  it("verifies a stream, rate limits it and reports failures", async () => {
    const r = await rig();
    const stream = await create(r, "poll");
    const url = "/ssf/verify";

    expect((await r.handle(call(url))).status).toBe(405);
    expect((await r.handle(call(url, "POST", {}))).status).toBe(400);

    expect(
      (await r.handle(call(url, "POST", { stream_id: stream.id, state: "s1" })))
        .status,
    ).toBe(204);

    const limited = await r.handle(call(url, "POST", { stream_id: stream.id }));
    expect(limited.status).toBe(429);
    expect(limited.headers.get("retry-after")).toBe("30");

    r.forced.set("note_ssf_verification", true);
    r.control.signerFails = true;
    expect(
      (await r.handle(call(url, "POST", { stream_id: stream.id, state: 5 })))
        .status,
    ).toBeGreaterThanOrEqual(500);

    r.forced.delete("note_ssf_verification");
    r.failing.add("note_ssf_verification");
    expect(
      (await r.handle(call(url, "POST", { stream_id: stream.id }))).status,
    ).toBeGreaterThanOrEqual(500);
  });

  it("serves a poll stream with acknowledgements and rejects the rest", async () => {
    const r = await rig();
    const stream = await create(r, "poll");
    const push = await create(r, "push");
    const url = `/ssf/poll/${stream.id}`;

    await r.transmitter
      .emit({
        subject: { format: "opaque", id: "u1" },
        event: { type: CAEP_EVENTS.sessionRevoked, claims: {} },
      })
      .orThrow();

    const first = await (
      await r.handle(call(url, "POST", { maxEvents: 5 }))
    ).json();

    const jti = Object.keys(first.sets)[0]!;
    expect(first.moreAvailable).toBe(false);

    await r.handle(
      call(url, "POST", {
        ack: [jti],
        setErrs: {
          bad: { err: "invalid_key", description: "x" },
          skipped: "nope",
          alsoSkipped: { err: 5 },
        },
      }),
    );

    expect(r.t.calls.at(-1)![1]).toMatchObject({
      ack: [jti],
      errors: { bad: { err: "invalid_key" } },
    });
    expect(
      (r.t.calls.at(-1)![1] as { errors: Record<string, unknown> }).errors,
    ).not.toHaveProperty("skipped");

    expect((await r.handle(call(url))).status).toBe(405);
    expect((await r.handle(call("/ssf/poll/nope", "POST"))).status).toBe(404);
    expect((await r.handle(call(`/ssf/poll/${push.id}`, "POST"))).status).toBe(
      404,
    );

    r.failing.add("poll_ssf_events");
    expect((await r.handle(call(url, "POST"))).status).toBeGreaterThanOrEqual(
      500,
    );
  });

  it("routes the well-known path, the base path and authorization", async () => {
    const r = await rig();

    expect(
      (
        await r.handle(
          new Request(`${ISSUER}/.well-known/ssf-configuration/ssf`, {
            method: "POST",
          }),
        )
      ).headers.get("allow"),
    ).toBe("GET");

    expect((await r.handle(call("/elsewhere"))).status).toBe(404);
    expect((await r.handle(call("/ssf/unknown"))).status).toBe(404);

    const anonymous = await r.handle(new Request(`${ISSUER}${STREAM}`));
    expect(anonymous.status).toBe(401);
  });
});
