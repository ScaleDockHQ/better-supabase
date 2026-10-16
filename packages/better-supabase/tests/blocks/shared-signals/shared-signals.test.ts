import { describe, expect, it, vi } from "vitest";

import type { VaultCredentials } from "../../../src/credentials/vault.ts";

import {
  CAEP_EVENTS,
  createSharedSignals,
  RISC_EVENTS,
  SSF_EVENTS,
  SSF_POLL,
  SSF_PUSH,
} from "../../../src/blocks/shared-signals/index.ts";
import { AsyncResult } from "../../../src/core/result.ts";
import { signingKey, store } from "./fixtures.ts";

const ISSUER = "https://tx.example";
const RECEIVER = { receiver: "rx", audience: "https://rx.example" };

async function setup(
  overrides: { credentials?: Pick<VaultCredentials, "set" | "revoke"> } = {},
) {
  const t = store();
  const { signer, jwks } = await signingKey();
  const blocks = createSharedSignals({ transport: t });
  const transmitter = blocks.transmitter({
    issuer: ISSUER,
    jwksUri: `${ISSUER}/jwks`,
    signer,
    authorize: (request) =>
      request.headers.get("authorization") === "Bearer rx" ? RECEIVER : null,
    ...overrides,
  });
  const handle = transmitter.handler();
  const http = vi.fn((input: RequestInfo | URL, init?: RequestInit) => {
    const request = new Request(input, init);
    return request.url === `${ISSUER}/jwks`
      ? Promise.resolve(Response.json(jwks))
      : handle(request);
  });
  return { t, jwks, transmitter, handle, http, blocks };
}

const request = (path: string, init: RequestInit = {}) => {
  const headers = new Headers(init.headers);
  headers.set("authorization", "Bearer rx");
  headers.set("content-type", "application/json");
  return new Request(`${ISSUER}${path}`, { ...init, headers });
};

describe("shared-signals transmitter", () => {
  it("publishes SSF 1.0 metadata at the well-known path", async () => {
    const { handle } = await setup();
    const response = await handle(
      new Request(`${ISSUER}/.well-known/ssf-configuration`),
    );
    expect(response.headers.get("cache-control")).toBe("public, max-age=300");
    expect(await response.json()).toEqual({
      spec_version: "1_0",
      issuer: ISSUER,
      jwks_uri: `${ISSUER}/jwks`,
      delivery_methods_supported: [SSF_PUSH, SSF_POLL],
      configuration_endpoint: `${ISSUER}/ssf/stream`,
      status_endpoint: `${ISSUER}/ssf/status`,
      verification_endpoint: `${ISSUER}/ssf/verify`,
      authorization_schemes: [{ spec_urn: "urn:ietf:rfc:6749" }],
      default_subjects: "ALL",
    });
  });

  it("answers 401 to a management request without a receiver", async () => {
    const { handle } = await setup();
    const response = await handle(
      new Request(`${ISSUER}/ssf/stream`, { method: "GET" }),
    );
    expect(response.status).toBe(401);
  });

  it("creates a poll stream that delivers only the supported events", async () => {
    const { handle } = await setup();
    const response = await handle(
      request("/ssf/stream", {
        method: "POST",
        body: JSON.stringify({
          delivery: { method: SSF_POLL },
          events_requested: [CAEP_EVENTS.sessionRevoked, "urn:unknown"],
          description: "IdP",
        }),
      }),
    );
    expect(response.status).toBe(201);
    const config = await response.json();
    expect(config).toMatchObject({
      iss: ISSUER,
      aud: "https://rx.example",
      events_requested: [CAEP_EVENTS.sessionRevoked, "urn:unknown"],
      events_delivered: [CAEP_EVENTS.sessionRevoked],
      delivery: {
        method: SSF_POLL,
        endpoint_url: `${ISSUER}/ssf/poll/${String(config.stream_id)}`,
      },
      min_verification_interval: 30,
      description: "IdP",
    });
    const listed = await handle(request("/ssf/stream"));
    expect(await listed.json()).toHaveLength(1);
  });

  it("hides another receiver's stream", async () => {
    const { handle, transmitter } = await setup();
    const other = await transmitter
      .createStream({
        receiver: { receiver: "someone-else" },
        method: "poll",
        eventsRequested: [],
      })
      .orThrow();
    const response = await handle(request(`/ssf/stream?stream_id=${other.id}`));
    expect(response.status).toBe(404);
  });

  it("stores a push stream's authorization header in Vault and revokes it on delete", async () => {
    const set = vi.fn(() => AsyncResult.ok(undefined));
    const revoke = vi.fn(() => AsyncResult.ok(true));
    const { handle, t } = await setup({
      // SAFETY: the transmitter calls only set and revoke.
      credentials: { set, revoke } as unknown as Pick<
        VaultCredentials,
        "set" | "revoke"
      >,
    });
    const response = await handle(
      request("/ssf/stream", {
        method: "POST",
        body: JSON.stringify({
          delivery: {
            method: SSF_PUSH,
            endpoint_url: "https://rx.example/ssf",
            authorization_header: "Bearer push-token",
          },
          events_requested: [RISC_EVENTS.accountDisabled],
        }),
      }),
    );
    expect(response.status).toBe(201);
    const { stream_id: id } = await response.json();
    expect(set).toHaveBeenCalledWith(
      {
        provider: "vault",
        secret: `ssf/${String(id)}`,
        header: "authorization",
        scheme: null,
      },
      "Bearer push-token",
    );
    const created = t.calls.find(([fn]) => fn === "create_ssf_stream")![1];
    expect(created["credential_ref"]).toMatchObject({
      secret: `ssf/${String(id)}`,
    });
    const deleted = await handle(
      request(`/ssf/stream?stream_id=${String(id)}`, { method: "DELETE" }),
    );
    expect(deleted.status).toBe(204);
    expect(revoke).toHaveBeenCalledWith(
      { provider: "vault", secret: `ssf/${String(id)}` },
      { subject: { type: "app" } },
    );
  });

  it("refuses a push stream without an https endpoint", async () => {
    const { handle } = await setup();
    const response = await handle(
      request("/ssf/stream", {
        method: "POST",
        body: JSON.stringify({
          delivery: { method: SSF_PUSH, endpoint_url: "http://rx.example" },
          events_requested: [],
        }),
      }),
    );
    expect(response.status).toBe(400);
  });

  it("emits to the tenant's streams and the app-wide ones", async () => {
    const { transmitter, t } = await setup();
    const make = (tenant: string | null, method: "push" | "poll") =>
      transmitter
        .createStream({
          receiver: { receiver: "rx", tenant },
          method,
          eventsRequested: [CAEP_EVENTS.sessionRevoked],
          ...(method === "push"
            ? { endpointUrl: "https://rx.example/ssf" }
            : {}),
        })
        .orThrow();
    await make("t1", "push");
    await make(null, "poll");
    await make("t2", "poll");
    const result = await transmitter
      .emit({
        tenant: "t1",
        subject: { format: "opaque", id: "u1" },
        event: { type: CAEP_EVENTS.sessionRevoked, claims: {} },
      })
      .orThrow();
    expect(result).toEqual({ streams: 2, dispatched: 1, queued: 1, held: 0 });
    expect(t.dispatched).toHaveLength(1);
  });

  it("sends stream-updated before pausing and after enabling", async () => {
    const { transmitter, t } = await setup();
    const stream = await transmitter
      .createStream({
        receiver: RECEIVER,
        method: "push",
        eventsRequested: [],
        endpointUrl: "https://rx.example/ssf",
      })
      .orThrow();
    expect(
      await transmitter.setStatus(stream.id, "paused", "maintenance").orThrow(),
    ).toBe("enabled");
    expect(t.dispatched).toHaveLength(1);
    await transmitter.verify(stream.id, "s1").orThrow();
    expect(t.queued).toHaveLength(1);
    await transmitter.setStatus(stream.id, "enabled").orThrow();
    const types = t.dispatched.map(
      ({ set }) =>
        Object.keys(
          JSON.parse(Buffer.from(set.split(".")[1]!, "base64url").toString())
            .events,
        )[0],
    );
    expect(types).toEqual([
      SSF_EVENTS.streamUpdated,
      SSF_EVENTS.verification,
      SSF_EVENTS.streamUpdated,
    ]);
  });

  it("rate-limits verification requests with 429 and Retry-After", async () => {
    const { handle, transmitter } = await setup();
    const stream = await transmitter
      .createStream({ receiver: RECEIVER, method: "poll", eventsRequested: [] })
      .orThrow();
    const verify = () =>
      handle(
        request("/ssf/verify", {
          method: "POST",
          body: JSON.stringify({ stream_id: stream.id, state: "x" }),
        }),
      );
    expect((await verify()).status).toBe(204);
    const limited = await verify();
    expect(limited.status).toBe(429);
    expect(limited.headers.get("retry-after")).toBe("30");
  });
});

describe("shared-signals receiver", () => {
  it("polls, verifies, handles and acknowledges SETs, and drops replays", async () => {
    const { transmitter, http, blocks, t } = await setup();
    const stream = await transmitter
      .createStream({
        receiver: RECEIVER,
        method: "poll",
        eventsRequested: [CAEP_EVENTS.sessionRevoked],
      })
      .orThrow();
    for (const id of ["u1", "u2", "u3"])
      await transmitter
        .emit({
          subject: { format: "opaque", id },
          event: { type: CAEP_EVENTS.sessionRevoked, claims: {} },
        })
        .orThrow();
    const seen: unknown[] = [];
    const receiver = blocks.receiver({
      issuer: ISSUER,
      audience: "https://rx.example",
      fetch: http,
      handlers: {
        [CAEP_EVENTS.sessionRevoked]: (set) => void seen.push(set.subject),
      },
    });
    const result = await receiver
      .poll({
        endpoint: `${ISSUER}/ssf/poll/${stream.id}`,
        authorization: "Bearer rx",
        maxEvents: 2,
      })
      .orThrow();
    expect(result).toEqual({
      received: 3,
      rejected: 0,
      failed: 0,
      moreAvailable: false,
    });
    expect(seen).toHaveLength(3);
    expect(t.queued).toHaveLength(0);
  });

  it("answers a push with 202, a replay with 202, and a bad SET with 400", async () => {
    const { transmitter, http, blocks, t } = await setup();
    await transmitter
      .createStream({
        receiver: RECEIVER,
        method: "push",
        eventsRequested: [CAEP_EVENTS.credentialChange],
        endpointUrl: "https://rx.example/ssf",
      })
      .orThrow();
    await transmitter
      .emit({
        subject: { format: "opaque", id: "u1" },
        event: { type: CAEP_EVENTS.credentialChange, claims: {} },
      })
      .orThrow();
    const handler = vi.fn();
    const push = blocks
      .receiver({
        issuer: ISSUER,
        audience: "https://rx.example",
        fetch: http,
        authorization: "Bearer push",
        handlers: { "*": handler },
      })
      .pushHandler();
    const send = (body: string, authorization = "Bearer push") =>
      push(
        new Request("https://rx.example/ssf", {
          method: "POST",
          headers: {
            authorization,
            "content-type": "application/secevent+jwt",
          },
          body,
        }),
      );
    const token = t.dispatched[0]!.set;
    expect((await send(token)).status).toBe(202);
    expect((await send(token)).status).toBe(202);
    expect(handler).toHaveBeenCalledTimes(1);
    const bad = await send("a.b.c");
    expect(bad.status).toBe(400);
    expect(await bad.json()).toMatchObject({ err: "invalid_request" });
    expect((await send(token, "Bearer wrong")).status).toBe(401);
  });

  it("forgets a SET whose handler threw, so the retry runs it", async () => {
    const { transmitter, http, blocks, t } = await setup();
    await transmitter
      .createStream({
        receiver: RECEIVER,
        method: "push",
        eventsRequested: [CAEP_EVENTS.credentialChange],
        endpointUrl: "https://rx.example/ssf",
      })
      .orThrow();
    await transmitter
      .emit({
        subject: { format: "opaque", id: "u1" },
        event: { type: CAEP_EVENTS.credentialChange, claims: {} },
      })
      .orThrow();
    let fail = true;
    const errors: string[] = [];
    const receiver = blocks.receiver({
      issuer: ISSUER,
      audience: "https://rx.example",
      fetch: http,
      logger: {
        debug: () => undefined,
        info: () => undefined,
        warn: () => undefined,
        error: (message) => void errors.push(message),
      },
      handlers: {
        "*": () => {
          if (fail) throw new Error("down");
        },
      },
    });
    const push = receiver.pushHandler();
    const send = () =>
      push(
        new Request("https://rx.example/ssf", {
          method: "POST",
          headers: { "content-type": "application/secevent+jwt" },
          body: t.dispatched[0]!.set,
        }),
      );
    expect((await send()).status).toBe(500);
    expect(errors).toHaveLength(1);
    fail = false;
    expect((await send()).status).toBe(202);
    expect(t.received.size).toBe(1);
  });

  it("checks the issuer in the transmitter metadata", async () => {
    const { blocks } = await setup();
    const receiver = blocks.receiver({
      issuer: ISSUER,
      audience: "rx",
      fetch: () =>
        Promise.resolve(Response.json({ issuer: "https://evil.example" })),
    });
    const result = await receiver.discover();
    expect(!result.ok && result.error.hint).toBe("SSF_ISSUER_MISMATCH");
  });

  it("creates a stream through the management API and checks its aud", async () => {
    const { http, blocks } = await setup();
    const client = blocks
      .receiver({ issuer: ISSUER, audience: "https://rx.example", fetch: http })
      .streams("Bearer rx");
    const config = await client
      .create({ method: "poll", eventsRequested: [CAEP_EVENTS.sessionRevoked] })
      .orThrow();
    const id = String(config["stream_id"]);
    expect(await client.status(id).orThrow()).toEqual({
      stream_id: id,
      status: "enabled",
    });
    expect(await client.verify(id).orThrow()).toBe(true);
    expect(await client.verify(id).orThrow()).toBe(false);
    await client.remove(id).orThrow();
    const wrong = await blocks
      .receiver({ issuer: ISSUER, audience: "other", fetch: http })
      .streams("Bearer rx")
      .create({ method: "poll", eventsRequested: [] });
    expect(!wrong.ok && wrong.error.hint).toBe("SSF_AUDIENCE_MISMATCH");
  });
});
