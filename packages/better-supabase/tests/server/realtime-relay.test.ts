import type { StandardSchemaV1 } from "@standard-schema/spec";

import { describe, expect, it, vi } from "vitest";

import type { AuthState } from "../../src/auth/resolve.ts";
import type {
  RelayAccessInput,
  RelayServer,
} from "../../src/server/realtime-relay.ts";
import type { ActiveSupport } from "../../src/server/support.ts";

import { defineTopic } from "../../src/realtime/index.ts";
import { relayRealtimeClient } from "../../src/realtime/relay.ts";
import {
  liveRelayTopic,
  realtimeRelay,
  realtimeTopicAccess,
} from "../../src/server/realtime-relay.ts";
import {
  fakeUpstream,
  inProcessEventSource,
  sseEvents,
} from "../fixtures/fake-relay.ts";
import { fakeSql, pgError } from "../fixtures/fake-sql.ts";

const title: StandardSchemaV1<unknown, { title: string }> = {
  "~standard": {
    version: 1,
    vendor: "test",
    validate: (value) =>
      typeof value === "object" &&
      value !== null &&
      "title" in value &&
      typeof value.title === "string"
        ? { value: { title: value.title } }
        : { issues: [{ message: "title is required", path: ["title"] }] },
  },
};

const notifications = defineTopic("org:{organizationId}:notes:{userId}", {
  events: { created: title },
  send: true,
});

const feed = defineTopic("feed:{organizationId}", { private: false });

const user = (sub: string, expiresAt: number | null = null): AuthState => ({
  kind: "user",
  token: "t",
  // SAFETY: the relay reads plain claims.
  claims: { sub, role: "authenticated", tenant_id: "o1" },
  // SAFETY: only `id` is read.
  user: { id: sub },
  source: "cookie",
  expiresAt,
});

const support = (readOnly: boolean): ActiveSupport => ({
  // SAFETY: the relay reads id, readOnly and expiresAt.
  session: {
    id: "s1",
    targetUserId: "target",
    readOnly,
    expiresAt: { epochMilliseconds: Date.now() + 60_000 },
  } as never,
  admin: { id: "admin" },
  claims: { sub: "target", role: "authenticated", tenant_id: "o1" },
});

function relayServer(
  auth: AuthState,
  upstream: ReturnType<typeof fakeUpstream>,
  active?: ActiveSupport,
): RelayServer {
  return {
    context: async () => ({
      auth: active ? user("target") : auth,
      resolution: { auth },
      ...(active ? { support: active } : {}),
      apply: (response) => response,
    }),
    admin: () => ({ $client: upstream.client }),
  };
}

const allowTarget = (seen: RelayAccessInput[]) => (input: RelayAccessInput) => {
  seen.push(input);

  return input.claims["sub"] === "target" || input.claims["sub"] === "u1";
};

const tick = (ms = 5) =>
  new Promise((resolve) => {
    setTimeout(resolve, ms);
  });

describe("realtimeRelay", () => {
  it("relays typed broadcasts to defineTopic subscriptions", async () => {
    const upstream = fakeUpstream();
    const seen: RelayAccessInput[] = [];

    const relay = realtimeRelay(relayServer(user("u1"), upstream), {
      topics: [notifications],
      authorize: allowTarget(seen),
    });

    const { EventSource } = inProcessEventSource(relay.GET);
    const client = relayRealtimeClient("/api/realtime", { EventSource });
    const created = vi.fn();
    const statuses: string[] = [];

    const sub = notifications.subscribe(
      client,
      { organizationId: "o1", userId: "u1" },
      { created },
      { onStatus: (status) => statuses.push(status) },
    );

    await sub.ready;
    upstream.emit("org:o1:notes:u1", "created", { title: "Hi" });
    upstream.emit("org:o1:notes:u1", "created", { nope: 1 });
    await tick();

    expect(created).toHaveBeenCalledExactlyOnceWith(
      { title: "Hi" },
      expect.objectContaining({ event: "created" }),
    );
    expect(statuses).toEqual(["joining", "subscribed"]);
    expect(seen).toMatchObject([
      { topic: "org:o1:notes:u1", action: "receive", support: undefined },
    ]);
    expect(upstream.open[0]?.config).toEqual({
      private: true,
      broadcast: { self: false },
    });

    await sub.unsubscribe();
    await tick();
    expect(upstream.open).toEqual([]);
  });

  it("checks a support session as the viewed user and refuses sends while read-only", async () => {
    const upstream = fakeUpstream();
    const seen: RelayAccessInput[] = [];

    const relay = realtimeRelay(
      relayServer(user("admin"), upstream, support(true)),
      { topics: [notifications], authorize: allowTarget(seen) },
    );

    const { EventSource } = inProcessEventSource(relay.GET);

    const client = relayRealtimeClient("/api/realtime", {
      EventSource,
      fetch: async (_url, init) =>
        relay.POST(new Request("https://app.test/api/realtime", init)),
    });

    const created = vi.fn();

    const sub = notifications.subscribe(
      client,
      { organizationId: "o1", userId: "target" },
      { created },
    );

    await sub.ready;
    upstream.emit("org:o1:notes:target", "created", { title: "Seen" });
    await tick();

    expect(created).toHaveBeenCalledOnce();
    expect(seen[0]).toMatchObject({
      action: "receive",
      claims: { sub: "target" },
      support: { session: { id: "s1" } },
    });

    expect(
      await notifications.send(
        client,
        { organizationId: "o1", userId: "target" },
        "created",
        { title: "From support" },
      ),
    ).toMatchObject({ ok: false, error: { kind: "forbidden" } });
    expect(upstream.sent).toEqual([]);

    await sub.unsubscribe();
  });

  it("sends for a caller allowed by the send check and validates the payload", async () => {
    const upstream = fakeUpstream();
    const seen: RelayAccessInput[] = [];

    const relay = realtimeRelay(relayServer(user("u1"), upstream), {
      topics: [notifications, feed],
      authorize: allowTarget(seen),
    });

    const post = (body: unknown) =>
      relay.POST(
        new Request("https://app.test/api/realtime", {
          method: "POST",
          body: JSON.stringify(body),
        }),
      );

    expect(
      (
        await post({
          topic: "org:o1:notes:u1",
          event: "created",
          payload: { title: "Hi" },
        })
      ).status,
    ).toBe(202);
    expect(upstream.sent).toEqual([
      { topic: "org:o1:notes:u1", event: "created", payload: { title: "Hi" } },
    ]);
    expect(seen.at(-1)).toMatchObject({ action: "send" });
    expect(upstream.open).toEqual([]);

    const invalid = await post({
      topic: "org:o1:notes:u1",
      event: "created",
      payload: {},
    });

    expect(invalid.status).toBe(422);
    expect((await post({ topic: "feed:o1", event: "x" })).status).toBe(403);
    expect((await post({ topic: "nope", event: "x" })).status).toBe(404);
    expect((await post({ event: "x" })).status).toBe(400);
  });

  it("refuses unknown topics, anonymous joins of private topics and denied callers", async () => {
    const upstream = fakeUpstream();

    const deny = realtimeRelay(relayServer(user("u2"), upstream), {
      topics: [notifications, feed],
      authorize: () => false,
    });

    const get = (topic?: string) =>
      new Request(
        `https://app.test/api/realtime${topic ? `?topic=${topic}` : ""}`,
      );

    expect((await deny.GET(get())).status).toBe(400);
    expect((await deny.GET(get("other:o1"))).status).toBe(404);
    expect((await deny.GET(get("org:o1:notes:u1"))).status).toBe(403);

    const anon = realtimeRelay(
      relayServer({ kind: "anon", reason: "none" }, upstream),
      { topics: [notifications, feed], authorize: () => true },
    );

    expect((await anon.GET(get("org:o1:notes:u1"))).status).toBe(401);

    const open = await anon.GET(get("feed:o1"));
    expect(open.status).toBe(200);
    await open.body?.cancel();

    const throwing = realtimeRelay(relayServer(user("u1"), upstream), {
      topics: [notifications],
      authorize: () => {
        throw new Error("boom");
      },
    });

    expect((await throwing.GET(get("org:o1:notes:u1"))).status).toBe(403);

    const { EventSource } = inProcessEventSource(deny.GET);
    const client = relayRealtimeClient("/api/realtime", { EventSource });

    const sub = notifications.subscribe(
      client,
      { organizationId: "o1", userId: "u1" },
      {},
    );

    await expect(sub.ready).rejects.toThrow("The relay refused");
  });

  it("needs postgres or authorize", () => {
    expect(() =>
      realtimeRelay(relayServer(user("u1"), fakeUpstream()), {
        topics: [notifications],
      }),
    ).toThrow("realtimeRelay needs `postgres`");
  });

  it("sends heartbeats and ends the stream when the session expires", async () => {
    const upstream = fakeUpstream();

    const relay = realtimeRelay(
      relayServer(user("u1", Math.floor(Date.now() / 1000) + 2), upstream),
      { topics: [notifications], authorize: () => true, heartbeatMs: 20 },
    );

    const response = await relay.GET(
      new Request("https://app.test/api/realtime?topic=org:o1:notes:u1"),
    );

    expect(response.headers.get("content-type")).toContain("text/event-stream");

    const events: string[] = [];

    for await (const message of sseEvents(response.body!)) {
      events.push(`${message.event}:${message.data}`);
    }

    expect(events[0]).toBe("retry:1000");
    expect(events).toContain('status:{"status":"subscribed","rejoin":false}');
    expect(events).toContain("comment:ping");
    expect(events.at(-1)).toBe('end:{"reason":"expired"}');
    expect(upstream.open).toEqual([]);
  });

  it("ends a stream that falls behind with overflow", async () => {
    const upstream = fakeUpstream();

    const relay = realtimeRelay(relayServer(user("u1"), upstream), {
      topics: [notifications],
      authorize: () => true,
      maxQueued: 2,
    });

    const response = await relay.GET(
      new Request("https://app.test/api/realtime?topic=org:o1:notes:u1"),
    );

    await tick();

    for (let i = 0; i < 5; i += 1) {
      upstream.emit("org:o1:notes:u1", "created", { title: String(i) });
    }

    const events: string[] = [];

    for await (const message of sseEvents(response.body!)) {
      events.push(message.event);
    }

    expect(events.at(-1)).toBe("end");
    expect(events.filter((event) => event === "broadcast").length).toBeLessThan(
      5,
    );
  });

  it("forwards presence states and reports a dropped upstream join", async () => {
    const upstream = fakeUpstream();
    const room = defineTopic("room:{roomId}", { presence: true });

    const relay = realtimeRelay(relayServer(user("u1"), upstream), {
      topics: [room],
      authorize: () => true,
    });

    const { EventSource } = inProcessEventSource(relay.GET);
    const client = relayRealtimeClient("/api/realtime", { EventSource });
    const onPresence = vi.fn();
    const sub = room.subscribe(client, { roomId: "r1" }, {}, { onPresence });
    await sub.ready;

    upstream.presence("room:r1", { k1: [{ presence_ref: "x", name: "Ann" }] });
    await tick();

    expect(onPresence).toHaveBeenLastCalledWith([
      { key: "k1", state: { name: "Ann" } },
    ]);
    expect(await sub.track({ name: "Me" })).toMatchObject({ ok: false });
    await sub.unsubscribe();

    upstream.refuse(true);

    const response = await relay.GET(
      new Request("https://app.test/api/realtime?topic=room:r2"),
    );

    const events: string[] = [];

    for await (const message of sseEvents(response.body!)) {
      events.push(`${message.event}:${message.data}`);
    }

    expect(events.at(-1)).toBe('end:{"reason":"upstream_error"}');
  });

  it("serves the live query channels", () => {
    expect(liveRelayTopic.match("bsb:t:public.customers:o1")).not.toBeNull();
    expect(liveRelayTopic.match("bsb:t:public.customers")).not.toBeNull();
    expect(liveRelayTopic.match("org:o1:notes:u1")).toBeNull();
  });
});

describe("realtimeTopicAccess", () => {
  const claims = { sub: "u1", role: "authenticated", tenant_id: "o1" };

  it("reads a probe message as the caller and rolls back", async () => {
    const fake = fakeSql([
      ["insert into realtime.messages", [{ id: "p1" }]],
      ["select exists", [{ allowed: true }]],
    ]);

    expect(
      await realtimeTopicAccess(fake.sql, {
        claims,
        topic: "org:o1:notes:u1",
        action: "receive",
      }),
    ).toBe(true);
    expect(fake.calls[0]?.values).toEqual(["org:o1:notes:u1", "broadcast"]);
    expect(fake.calls[1]?.values).toEqual([
      JSON.stringify(claims),
      "u1",
      "authenticated",
      "org:o1:notes:u1",
    ]);
    expect(fake.calls[2]?.values).toEqual(["p1"]);
  });

  it("denies a send the insert policy refuses and rethrows other errors", async () => {
    const denied = fakeSql([
      [
        "insert into realtime.messages",
        { throws: pgError("42501", "new row violates row-level security") },
      ],
    ]);

    expect(
      await realtimeTopicAccess(denied.sql, {
        claims: { role: "anon" },
        topic: "t",
        action: "send",
      }),
    ).toBe(false);
    expect(denied.calls[0]?.values[2]).toBe("anon");

    const allowed = fakeSql([]);

    expect(
      await realtimeTopicAccess(allowed.sql, {
        claims,
        topic: "t",
        action: "send",
      }),
    ).toBe(true);

    const broken = fakeSql([
      ["insert into realtime.messages", { throws: pgError("42P01", "gone") }],
    ]);

    await expect(
      realtimeTopicAccess(broken.sql, { claims, topic: "t", action: "send" }),
    ).rejects.toThrow("gone");
  });
});
