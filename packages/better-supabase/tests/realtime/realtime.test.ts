import type { StandardSchemaV1 } from "@standard-schema/spec";

import { describe, expect, it, vi } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { DbException } from "../../src/core/errors.ts";
import {
  defineTopic,
  type RealtimeClient,
  rowChange,
  rowKeys,
} from "../../src/realtime/index.ts";
import { LOOKUP_WARNING } from "../../src/realtime/topic-trigger.ts";
import { schema, topics } from "../fixtures/generated-camel.ts";

const betterSupabase = defineSupabase(schema);

const SQL = {
  idsWith: "authz.ids_{scope}({permission})",
  isPlatform: "authz.is_platform({permission})",
};

const title: StandardSchemaV1<unknown, { title: string }> = {
  "~standard": {
    version: 1,
    vendor: "test",
    validate: (value) =>
      typeof (value as { title?: unknown } | null)?.title === "string"
        ? { value: { title: (value as { title: string }).title } }
        : {
            issues: [
              { message: "title is required", path: [{ key: "title" }] },
            ],
          },
  },
};

type Listener = (message: { event: string; payload: unknown }) => void;

type SendAnswer =
  | { success: true }
  | { success: false; status: number; error: string };

function fakeClient(
  status: string = "SUBSCRIBED",
  error: Error | null = status === "SUBSCRIBED"
    ? null
    : new Error("Unauthorized"),
) {
  const listeners: Listener[] = [];
  const syncs: (() => void)[] = [];
  const removed: unknown[] = [];
  const open: unknown[] = [];
  let presence: Record<string, Record<string, unknown>[]> = {};
  let report: ((status: string, error?: Error) => void) | undefined;

  const channel = {
    topic: "",
    on: vi.fn((type: string, _filter: unknown, listener: Listener) => {
      if (type === "presence") {
        syncs.push(listener as () => void);
      } else {
        listeners.push(listener);
      }

      return channel;
    }),
    presenceState: () => presence,
    track: vi.fn(async (_state: unknown): Promise<string> => "ok"),
    untrack: vi.fn(async (): Promise<string> => "ok"),
    subscribe: vi.fn((callback: (status: string, error?: Error) => void) => {
      open.push(channel);
      report = callback;
      queueMicrotask(() => {
        callback(status, error ?? undefined);
      });

      return channel;
    }),
    httpSend: vi.fn(
      async (_event: string, _payload: unknown): Promise<SendAnswer> => ({
        success: true,
      }),
    ),
  };

  const client = {
    channel: vi.fn((topic: string) => {
      if (!open.includes(channel)) {
        channel.topic = `realtime:${topic}`;
      }

      return channel;
    }),
    getChannels: vi.fn(() => open),
    removeChannel: vi.fn(async (value: unknown) => {
      removed.push(value);
      open.splice(open.indexOf(value), 1);
      report?.("CLOSED");

      return "ok" as const;
    }),
    realtime: { setAuth: vi.fn(async () => undefined) },
  };

  const emit = (event: string, payload: unknown) => {
    for (const listener of listeners) {
      listener({ event, payload });
    }
  };

  const sync = (state: Record<string, Record<string, unknown>[]>) => {
    presence = state;

    for (const listener of syncs) {
      listener();
    }
  };

  return {
    client: client as unknown as RealtimeClient,
    raw: client,
    channel,
    emit,
    sync,
    removed,
  };
}

const flush = () =>
  new Promise((resolve) => {
    setTimeout(resolve, 0);
  });

describe("defineTopic", () => {
  const notifications = defineTopic(topics.notifications, {
    events: { created: title },
    send: true,
  });

  it("exposes what the AsyncAPI document reads", () => {
    expect(notifications.events).toEqual({ created: title });
    expect(notifications.clientSend).toBe(true);
    expect(notifications.permission).toBeUndefined();
    expect(notifications.presenceSchema).toBeUndefined();
    expect(notifications.status).toBe("beta");

    const lobby = defineTopic("lobby:{roomId}", {
      private: false,
      presence: title,
      permission: { key: "rooms.read" },
    });

    expect(lobby.events).toEqual({});
    expect(lobby.clientSend).toBe(false);
    expect(lobby.permission).toBe("rooms.read");
    expect(lobby.presenceSchema).toBe(title);
    expect(lobby.status).toBe("ga");
  });

  it("builds and matches topic names", () => {
    expect(notifications.topic({ organizationId: "o1", userId: "u1" })).toBe(
      "organization:o1:notifications:u1",
    );
    expect(notifications.match("organization:o1:notifications:u1")).toEqual({
      organizationId: "o1",
      userId: "u1",
    });
    expect(notifications.match("organization:o1:notifications")).toBeNull();
    expect(() =>
      notifications.topic({ organizationId: "o:1", userId: "u1" }),
    ).toThrow(DbException);
    expect(notifications.name).toBe("organization_notifications");
  });

  it("generates policies with tenant and owner checks", () => {
    const sql = notifications.sql();
    expect(sql).toContain(
      'create policy "bs_topic_organization_notifications_receive" on realtime.messages for select to authenticated',
    );
    expect(sql).toContain(
      'create policy "bs_topic_organization_notifications_send" on realtime.messages for insert to authenticated',
    );
    expect(sql).toContain(
      "(select realtime.topic()) ~ '^organization:[^:]+:notifications:[^:]+$'",
    );
    expect(sql).toContain(
      "split_part((select realtime.topic()), ':', 2) = (coalesce((select auth.jwt()) ->> 'tenant_id'",
    );
    expect(sql).toContain(
      "split_part((select realtime.topic()), ':', 4) = (select auth.uid())::text",
    );
    const open = defineTopic("room:{roomId}").sql();
    expect(open).not.toContain("split_part");
    expect(open).not.toContain("for insert");
  });

  it("compiles access receive and send policies", () => {
    const board = defineTopic("organization:{organizationId}:board", {
      access: {
        receive: "board.read",
        send: "board.write",
        scope: "organization",
        sql: SQL,
      },
    }).sql();

    const ids = (key: string) =>
      `split_part((select realtime.topic()), ':', 2) in (select t.id::text from authz.ids_organization('${key}') as t(id))`;

    expect(board).toContain(
      `for select to authenticated\n  using (\n    (select realtime.topic()) ~ '^organization:[^:]+:board$'\n    and realtime.messages.extension in ('broadcast')\n    and ${ids("board.read")}\n  );`,
    );
    expect(board).toContain(`for insert to authenticated\n  with check (`);
    expect(board).toContain(ids("board.write"));
    expect(board).not.toContain("tenant_id");
    expect(board).not.toContain("service_role");

    const receiveOnly = defineTopic("announcements", {
      access: { receive: "announcements.read", scope: "platform", sql: SQL },
    }).sql();

    expect(receiveOnly).toContain(
      `(select authz.is_platform('announcements.read'))`,
    );
    expect(receiveOnly).not.toContain("for insert");
    expect(() =>
      defineTopic("organization:{organizationId}", {
        access: { receive: "", scope: "organization", sql: SQL },
      }),
    ).toThrow(/empty/);
    expect(() =>
      defineTopic("organization:{organizationId}", {
        access: { receive: "x.read", scope: "org; drop", sql: SQL },
      }),
    ).toThrow(/invalid scope/);
  });

  it('renders sql: "provider" with the templates sql() receives', () => {
    const topic = defineTopic("organization:{organizationId}:board", {
      access: { receive: "board.read", scope: "organization", sql: "provider" },
    });

    expect(() => topic.sql()).toThrow(/sql "provider" needs `authorization`/);
    expect(topic.sql({ functions: SQL })).toContain(
      "in (select t.id::text from authz.ids_organization('board.read') as t(id))",
    );
  });

  it("generates a row-change trigger with database column names", () => {
    const sql = defineTopic(topics.customers).trigger("customers", {
      betterSupabase,
      values: { organizationId: "organizationId" },
    });

    expect(sql).toContain('create schema if not exists "better_supabase";');
    expect(sql).toContain(
      'create or replace function "better_supabase"."bs_broadcast_organization_customers_public_customers"()',
    );
    expect(sql).toContain(
      `vals := jsonb_build_object('organizationId', (rec."organization_id")::text);`,
    );
    expect(sql).toContain(
      'create trigger "bs_broadcast_organization_customers" after insert or update or delete on "public"."customers"',
    );
  });

  it("dispatches validated payloads and disposes the channel", async () => {
    const { client, raw, emit, removed } = fakeClient();
    const created = vi.fn();
    const other = vi.fn();
    const onInvalid = vi.fn();
    {
      using subscription = notifications.subscribe(
        client,
        { organizationId: "o1", userId: "u1" },
        { created, "*": other },
        { onInvalid },
      );

      await subscription.ready;
      expect(raw.realtime.setAuth).toHaveBeenCalled();
      expect(raw.channel).toHaveBeenCalledWith(
        "organization:o1:notifications:u1",
        {
          config: { private: true, broadcast: { self: false } },
        },
      );
      emit("created", { title: "Hi", extra: 1 });
      emit("created", { nope: true });
      emit("deleted", { id: 1 });
      await flush();
    }

    expect(created).toHaveBeenCalledWith(
      { title: "Hi" },
      {
        event: "created",
        payload: { title: "Hi", extra: 1 },
        topic: "organization:o1:notifications:u1",
      },
    );
    expect(onInvalid).toHaveBeenCalledWith(
      expect.objectContaining({ event: "created" }),
      [{ message: "title is required", path: ["title"] }],
    );
    expect(other).toHaveBeenCalledWith(
      { id: 1 },
      expect.objectContaining({ event: "deleted" }),
    );
    await flush();
    expect(removed).toHaveLength(1);
  });

  it("shares one channel per topic and removes it after the last subscription", async () => {
    const { client, raw, channel, emit, removed } = fakeClient();
    const values = { organizationId: "o1", userId: "u1" };
    const first = vi.fn();
    const second = vi.fn();
    const statuses: string[] = [];
    const a = notifications.subscribe(client, values, { "*": first });
    await a.ready;

    const b = notifications.subscribe(
      client,
      values,
      { "*": second },
      { onStatus: (status) => statuses.push(status) },
    );

    await b.ready;
    expect(raw.channel).toHaveBeenCalledTimes(1);
    expect(channel.subscribe).toHaveBeenCalledTimes(1);
    expect(statuses).toEqual(["joining", "subscribed"]);
    emit("deleted", { id: 1 });
    await flush();
    expect(first).toHaveBeenCalledTimes(1);
    expect(second).toHaveBeenCalledTimes(1);
    await a.unsubscribe();
    expect(removed).toHaveLength(0);
    emit("deleted", { id: 2 });
    await flush();
    expect(second).toHaveBeenCalledTimes(2);
    expect(first).toHaveBeenCalledTimes(1);
    await b.unsubscribe();
    expect(removed).toHaveLength(1);
    expect(() =>
      notifications.subscribe(client, values, {}, { self: true }),
    ).not.toThrow();
  });

  it("refuses a second subscription with a different self", async () => {
    const { client } = fakeClient();
    const values = { organizationId: "o1", userId: "u1" };
    using first = notifications.subscribe(client, values, {});
    expect(first.topic).toBe("organization:o1:notifications:u1");
    expect(() =>
      notifications.subscribe(client, values, {}, { self: true }),
    ).toThrow(/same `self`/);
  });

  it("drops a channel that never joined so the next subscribe starts over", async () => {
    const { client, raw, removed } = fakeClient("TIMED_OUT");
    const values = { organizationId: "o1", userId: "u1" };
    const failed = notifications.subscribe(client, values, {});
    await expect(failed.ready).rejects.toThrow("Unauthorized");
    expect(removed).toHaveLength(1);
    const again = notifications.subscribe(client, values, {});
    await expect(again.ready).rejects.toThrow("Unauthorized");
    expect(raw.channel).toHaveBeenCalledTimes(2);
  });

  it("rejects ready when the join is refused", async () => {
    const { client } = fakeClient("CHANNEL_ERROR");
    const statuses: string[] = [];

    const subscription = notifications.subscribe(
      client,
      { organizationId: "o1", userId: "u1" },
      {},
      { onStatus: (status) => statuses.push(status) },
    );

    await expect(subscription.ready).rejects.toThrow("Unauthorized");
    expect(statuses).toEqual(["joining", "error"]);
  });

  it("validates before sending", async () => {
    const { client, channel } = fakeClient();

    const invalid = await notifications.send(
      client,
      { organizationId: "o1", userId: "u1" },
      "created",
      {},
    );

    expect(invalid.error?.kind).toBe("validation");
    expect(channel.httpSend).not.toHaveBeenCalled();
    await notifications
      .send(client, { organizationId: "o1", userId: "u1" }, "created", {
        title: "Hi",
      })
      .orThrow();
    expect(channel.httpSend).toHaveBeenCalledWith("created", { title: "Hi" });
  });

  it("keeps a subscribed channel open when sending on its topic", async () => {
    const { client, raw } = fakeClient();

    const subscription = notifications.subscribe(
      client,
      { organizationId: "o1", userId: "u1" },
      {},
    );

    await subscription.ready;
    raw.realtime.setAuth.mockClear();
    await notifications
      .send(client, { organizationId: "o1", userId: "u1" }, "created", {
        title: "Hi",
      })
      .orThrow();
    expect(raw.removeChannel).not.toHaveBeenCalled();
    expect(raw.realtime.setAuth).not.toHaveBeenCalled();
    await subscription.unsubscribe();
    expect(raw.removeChannel).toHaveBeenCalledTimes(1);
  });

  it("maps failed sends to DbError kinds and removes the channel", async () => {
    const room = defineTopic("room:{roomId}", { private: false });

    const cases: [number, string, number][] = [
      [401, "unauthorized", 401],
      [403, "forbidden", 403],
      [429, "network", 429],
      [502, "network", 502],
      [0, "network", 503],
      [418, "invalid_request", 418],
    ];

    for (const [status, kind, reported] of cases) {
      const { client, raw, channel, removed } = fakeClient();
      channel.httpSend.mockResolvedValueOnce({
        success: false,
        status,
        error: `failed ${status}`,
      });
      const result = await room.send(client, { roomId: "r1" }, "ping", {});
      expect(result.error).toMatchObject({ kind, message: `failed ${status}` });
      expect((result.error as { status?: number } | null)?.status).toBe(
        reported,
      );
      expect(raw.realtime.setAuth).not.toHaveBeenCalled();
      expect(raw.channel).toHaveBeenCalledWith("room:r1", {
        config: { private: false },
      });
      expect(removed).toEqual([channel]);
    }
  });

  it("joins public topics without setAuth and passes self", async () => {
    const room = defineTopic("room:{roomId}", { private: false });
    const { client, raw, channel } = fakeClient();

    const subscription = room.subscribe(
      client,
      { roomId: "r1" },
      {},
      { self: true },
    );

    await subscription.ready;
    expect(channel.subscribe).toHaveBeenCalledTimes(1);
    expect(raw.realtime.setAuth).not.toHaveBeenCalled();
    expect(raw.channel).toHaveBeenCalledWith("room:r1", {
      config: { private: false, broadcast: { self: true } },
    });
  });

  it("ignores events without a handler and validates nothing for unknown events", async () => {
    const { client, emit } = fakeClient();
    const created = vi.fn();

    const subscription = notifications.subscribe(
      client,
      { organizationId: "o1", userId: "u1" },
      { created },
    );

    await subscription.ready;
    emit("deleted", { id: 1 });
    emit("created", { title: "Yo" });
    await flush();
    expect(created).toHaveBeenCalledTimes(1);
    expect(created).toHaveBeenCalledWith({ title: "Yo" }, expect.anything());
  });

  it("reports issues without a path and keeps numeric path parts", async () => {
    const strict: StandardSchemaV1 = {
      "~standard": {
        version: 1,
        vendor: "test",
        validate: (value) =>
          value === "flat"
            ? { issues: [{ message: "flat issue" }] }
            : { issues: [{ message: "deep issue", path: [0, "x"] }] },
      },
    };

    const topic = defineTopic("room:{roomId}", { events: { msg: strict } });
    const { client, emit } = fakeClient();
    const onInvalid = vi.fn();

    const subscription = topic.subscribe(
      client,
      { roomId: "r1" },
      { msg: vi.fn() },
      { onInvalid },
    );

    await subscription.ready;
    emit("msg", "flat");
    emit("msg", "deep");
    await flush();
    expect(onInvalid.mock.calls.map((call) => call[1])).toEqual([
      [{ message: "flat issue" }],
      [{ message: "deep issue", path: [0, "x"] }],
    ]);
    // Without onInvalid an invalid payload is dropped.
    const quiet = topic.subscribe(client, { roomId: "r1" }, { msg: vi.fn() });
    await quiet.ready;
    emit("msg", "flat");
    await flush();
  });

  it("resolves ready on CLOSED and names a refusal without an error", async () => {
    const closed = fakeClient("CLOSED");
    const statuses: string[] = [];

    const subscription = notifications.subscribe(
      closed.client,
      { organizationId: "o1", userId: "u1" },
      {},
      { onStatus: (status) => statuses.push(status) },
    );

    await subscription.ready;
    expect(statuses).toEqual(["joining", "closed"]);

    const timedOut = fakeClient("TIMED_OUT", null);
    await expect(
      notifications.subscribe(
        timedOut.client,
        { organizationId: "o1", userId: "u1" },
        {},
      ).ready,
    ).rejects.toThrow("Realtime timed_out on organization:o1:notifications:u1");

    const weird = fakeClient("WEIRD", null);
    await expect(
      notifications.subscribe(
        weird.client,
        { organizationId: "o1", userId: "u1" },
        {},
      ).ready,
    ).rejects.toThrow("Unknown realtime status WEIRD");
  });

  it("skips the join when unsubscribed during setAuth and unsubscribes once", async () => {
    const { client, raw, channel } = fakeClient();
    let release: () => void = () => undefined;
    raw.realtime.setAuth.mockImplementationOnce(
      () =>
        new Promise<undefined>((resolve) => {
          release = () => {
            resolve(undefined);
          };
        }),
    );

    const subscription = notifications.subscribe(
      client,
      { organizationId: "o1", userId: "u1" },
      {},
    );

    await subscription.unsubscribe();
    await subscription.unsubscribe();
    release();
    await subscription.ready;
    expect(channel.subscribe).not.toHaveBeenCalled();
    expect(raw.removeChannel).toHaveBeenCalledTimes(1);
  });

  it("disposes asynchronously with await using", async () => {
    const { client, removed } = fakeClient();
    {
      await using subscription = notifications.subscribe(
        client,
        { organizationId: "o1", userId: "u1" },
        {},
      );

      await subscription.ready;
    }

    expect(removed).toHaveLength(1);
  });
});

describe("presence", () => {
  const cursor: StandardSchemaV1<unknown, { name: string }> = {
    "~standard": {
      version: 1,
      vendor: "test",
      validate: (value) =>
        typeof (value as { name?: unknown } | null)?.name === "string"
          ? { value: { name: (value as { name: string }).name } }
          : { issues: [{ message: "name is required" }] },
    },
  };

  const room = defineTopic("room:{roomId}", { presence: cursor });
  const values = { roomId: "r1" };

  it("listens for presence only on presence topics", async () => {
    const { client, channel } = fakeClient();
    using plain = defineTopic("plain:{roomId}").subscribe(client, values, {});
    await plain.ready;
    expect(channel.on).not.toHaveBeenCalledWith(
      "presence",
      expect.anything(),
      expect.anything(),
    );
    expect("track" in plain).toBe(false);
    expect(room.presence).toBe(true);
  });

  it("delivers validated members on sync and reports invalid states", async () => {
    const { client, sync } = fakeClient();
    const onPresence = vi.fn();
    const onInvalid = vi.fn();

    using subscription = room.subscribe(
      client,
      values,
      {},
      { onPresence, onInvalid },
    );

    await subscription.ready;
    sync({
      a: [{ presence_ref: "1", name: "Ada", extra: true }],
      b: [{ presence_ref: "2", nope: 1 }],
    });
    await flush();
    expect(onPresence).toHaveBeenCalledWith([
      { key: "a", state: { name: "Ada" } },
    ]);
    expect(subscription.members()).toEqual([
      { key: "a", state: { name: "Ada" } },
    ]);
    expect(onInvalid).toHaveBeenCalledWith(
      { event: "presence", payload: { nope: 1 }, topic: "room:r1" },
      [{ message: "name is required" }],
    );
  });

  it("gives a late subscriber the last synced state", async () => {
    const { client, sync } = fakeClient();
    using first = room.subscribe(client, values, {});
    await first.ready;
    sync({ a: [{ presence_ref: "1", name: "Ada" }] });
    const onPresence = vi.fn();
    using second = room.subscribe(client, values, {}, { onPresence });
    await flush();
    expect(onPresence).toHaveBeenCalledWith([
      { key: "a", state: { name: "Ada" } },
    ]);
    expect(second.members()).toHaveLength(1);
  });

  it("keeps only the newest sync when validation finishes out of order", async () => {
    const { client, sync } = fakeClient();
    let release: (() => void) | undefined;

    const slow: StandardSchemaV1<unknown, unknown> = {
      "~standard": {
        version: 1,
        vendor: "test",
        validate: (value) =>
          (value as { slow?: boolean }).slow
            ? new Promise((resolve) => {
                release = () => {
                  resolve({ value });
                };
              })
            : { value },
      },
    };

    const onPresence = vi.fn();

    using subscription = defineTopic("slow:{roomId}", {
      presence: slow,
    }).subscribe(client, values, {}, { onPresence });

    await subscription.ready;
    sync({ a: [{ presence_ref: "1", slow: true }] });
    sync({ b: [{ presence_ref: "2" }] });
    await flush();
    release?.();
    await flush();
    expect(onPresence).toHaveBeenCalledTimes(1);
    expect(subscription.members()).toEqual([{ key: "b", state: {} }]);
  });

  it("validates, then tracks and untracks after the join", async () => {
    const { client, channel } = fakeClient();
    using subscription = room.subscribe(client, values, {});
    const bad = await subscription.track({ name: 1 });
    expect(bad.ok ? null : bad.error.kind).toBe("validation");
    expect(channel.track).not.toHaveBeenCalled();
    expect((await subscription.track({ name: "Ada" })).ok).toBe(true);
    expect(channel.track).toHaveBeenCalledWith({ name: "Ada" });
    expect((await subscription.untrack()).ok).toBe(true);
    expect(channel.untrack).toHaveBeenCalledTimes(1);
  });

  it("maps a refused join, a failed send and a closed subscription to errors", async () => {
    const refused = fakeClient("CHANNEL_ERROR");
    const failed = room.subscribe(refused.client, values, {});
    await failed.ready.catch(() => undefined);
    const join = await failed.track({ name: "Ada" });
    expect(join.ok ? null : join.error).toMatchObject({
      kind: "network",
      details: "Unauthorized",
    });
    await failed.unsubscribe();

    const { client, channel } = fakeClient();
    const subscription = room.subscribe(client, values, {});
    channel.track.mockResolvedValueOnce("timed out");
    const timedOut = await subscription.track({ name: "Ada" });
    expect(timedOut.ok ? null : timedOut.error.message).toBe(
      "Presence track timed out on room:r1",
    );
    await subscription.unsubscribe();
    const closed = await subscription.untrack();
    expect(closed.ok ? null : closed.error.kind).toBe("invalid_request");
  });

  it("untracks a leaving tracker while others stay on the channel", async () => {
    const { client, channel, removed } = fakeClient();
    const tracker = room.subscribe(client, values, {});
    const other = room.subscribe(client, values, {});
    await tracker.track({ name: "Ada" });
    await other.unsubscribe();
    expect(channel.untrack).not.toHaveBeenCalled();
    const again = room.subscribe(client, values, {});
    await tracker.unsubscribe();
    expect(channel.untrack).toHaveBeenCalledTimes(1);
    await again.unsubscribe();
    expect(removed).toHaveLength(1);
  });

  it("refuses to share a topic between presence and plain definitions", async () => {
    const { client } = fakeClient();
    using subscription = room.subscribe(client, values, {});
    expect(subscription.topic).toBe("room:r1");
    expect(() =>
      defineTopic("room:{roomId}").subscribe(client, values, {}),
    ).toThrow(/same `presence`/);
  });

  it("accepts any object state with presence: true", async () => {
    const { client, channel, sync } = fakeClient();
    const onPresence = vi.fn();

    using subscription = defineTopic("open:{roomId}", {
      presence: true,
    }).subscribe(client, values, {}, { onPresence });

    await subscription.track({ anything: 1 });
    expect(channel.track).toHaveBeenCalledWith({ anything: 1 });
    sync({ k: [{ presence_ref: "1", anything: 1 }] });
    await flush();
    expect(onPresence).toHaveBeenCalledWith([
      { key: "k", state: { anything: 1 } },
    ]);
  });
});

describe("defineTopic policies", () => {
  it("falls back to the name 'topic' for an all-parameter template", () => {
    expect(defineTopic("{roomId}").name).toBe("topic");
    expect(defineTopic("room:{roomId}", { name: "Lobby" }).name).toBe("lobby");
  });

  it("uses a custom tenant claim, param or SQL", () => {
    expect(
      defineTopic("team:{teamId}", {
        tenant: { param: "teamId", claim: "app_metadata.team_id" },
      }).sql(),
    ).toContain(
      "split_part((select realtime.topic()), ':', 2) = ((select auth.jwt()) -> 'app_metadata' ->> 'team_id')",
    );
    expect(
      defineTopic("organization:{organizationId}", {
        tenant: { sql: "private.org_id()" },
      }).sql(),
    ).toContain(
      "split_part((select realtime.topic()), ':', 2) = (private.org_id())",
    );
  });

  it("throws when a checked parameter is not a whole segment", () => {
    expect(() =>
      defineTopic("organization-{organizationId}", { tenant: {} }),
    ).toThrow(
      /the tenant check needs \{organizationId\} as a whole segment in "organization-\{organizationId\}"/,
    );
    expect(() => defineTopic("user-{userId}", { owner: {} })).toThrow(
      /the owner check needs \{userId\}/,
    );
    expect(() =>
      defineTopic("organization-{organizationId}", {
        access: { receive: "a.read", scope: "organization", sql: SQL },
      }),
    ).toThrow(/the access check needs \{organizationId\}/);
  });

  it("drops the tenant and owner checks when disabled", () => {
    const sql = defineTopic("organization:{organizationId}:inbox:{userId}", {
      tenant: false,
      owner: false,
    }).sql();

    expect(sql).not.toContain("split_part");
  });

  it("uses an explicit access segment and the default organizationId without a tenant", () => {
    expect(
      defineTopic("x:{a}:{organizationId}", {
        tenant: false,
        access: { receive: "a.read", scope: "organization", sql: SQL },
      }).sql(),
    ).toContain("split_part((select realtime.topic()), ':', 3) in");
    expect(
      defineTopic("x:{a}:{b}", {
        access: {
          receive: "a.read",
          scope: "organization",
          segment: 2,
          sql: SQL,
        },
      }).sql(),
    ).toContain("split_part((select realtime.topic()), ':', 2) in");
  });

  it("authorizes presence and adds a send policy for it", () => {
    const sql = defineTopic("room:{roomId}", { presence: true }).sql();
    expect(sql).toContain(
      "realtime.messages.extension in ('broadcast', 'presence')",
    );
    expect(sql).toContain(
      '"bs_topic_room_send" on realtime.messages for insert',
    );
  });
});

describe("trigger with betterSupabase", () => {
  const customers = defineTopic(topics.customers);

  it("rejects unknown tables and unmapped parameters", () => {
    expect(() =>
      customers.trigger("nope", {
        // @ts-expect-error unknown table
        betterSupabase,
        values: { organizationId: "id" },
      }),
    ).toThrow('defineTopic: unknown table "nope"');
    expect(() =>
      customers.trigger("customers", {
        // @ts-expect-error missing value
        betterSupabase,
        values: {},
      }),
    ).toThrow("defineTopic: no column for {organizationId}");
    expect(() =>
      customers.trigger("customers", {
        // @ts-expect-error unknown column
        betterSupabase,
        values: { organizationId: "missing" },
      }),
    ).toThrow("defineTopic: no column for {organizationId}");
  });

  it("sends the primary key and the placeholder values by default", () => {
    const sql = customers.trigger("customers", {
      betterSupabase,
      values: { organizationId: "organizationId" },
    });

    expect(sql).toContain(
      `vals := jsonb_build_object('organizationId', (rec."organization_id")::text);`,
    );
    expect(sql).toContain(
      `perform realtime.send(jsonb_build_object('operation', tg_op, 'schema', tg_table_schema, 'table', tg_table_name, 'id', to_jsonb(rec."id"), 'values', vals), tg_op, 'organization:' || (vals ->> 'organizationId') || ':customers', true);`,
    );
    expect(sql).not.toContain("old_record");
    expect(sql).not.toContain("broadcast_changes");
    expect(sql).toContain("if tg_when <> 'AFTER' then");
  });

  it("names composite keys by column and reads no key for a keyless table", () => {
    const tagged = defineTopic("customer:{customerId}");

    const sql = tagged.trigger("customerTags", {
      betterSupabase,
      values: { customerId: "customerId" },
    });

    expect(sql).toContain(
      `'id', jsonb_build_object('customer_id', rec."customer_id", 'tag_id', rec."tag_id")`,
    );
  });

  it("sends whole rows only with payload: row, and marks the function", () => {
    const sql = customers.trigger("customers", {
      betterSupabase,
      values: { organizationId: "organizationId" },
      payload: "row",
    });

    expect(sql).toContain(
      "jsonb_build_object('old_record', old, 'record', new, 'operation', tg_op, 'table', tg_table_name, 'schema', tg_table_schema)",
    );
    expect(sql).toContain(
      `comment on function "better_supabase"."bs_broadcast_organization_customers_public_customers"() is 'better-supabase: payload row';`,
    );
  });

  it("skips a topic with a null or disallowed value instead of failing the write", () => {
    const sql = customers.trigger("customers", {
      betterSupabase,
      values: { organizationId: "organizationId" },
    });

    expect(sql).toContain(
      "where e.value is null or e.value !~ '^[\\w.@+=-]+$'",
    );
    expect(sql).toContain("raise warning 'skipped the broadcast on %");
    expect(sql).not.toContain("raise exception 'topic value");
  });

  it("fans one row out to several topics, each skipped on its own", () => {
    const owner = defineTopic("user:{userId}:customers", { private: false });

    const sql = customers.trigger("customers", {
      betterSupabase,
      values: { organizationId: "organizationId" },
      topics: [{ topic: owner, values: { userId: "id" } }],
    });

    expect(sql).toContain(
      "-- better-supabase: broadcast customers changes to organization:{organizationId}:customers, user:{userId}:customers",
    );
    expect(sql.match(/perform realtime\.send/g)).toHaveLength(2);
    expect(sql).toContain(
      `vals := jsonb_build_object('userId', (rec."id")::text);`,
    );
    expect(sql).toContain(
      "'user:' || (vals ->> 'userId') || ':customers', false);",
    );
    expect(() =>
      customers.trigger("customers", {
        betterSupabase,
        values: { organizationId: "organizationId" },
        topics: [{ topic: owner, values: {} }],
      }),
    ).toThrow("no column for {userId} of user:{userId}:customers");
    expect(() =>
      customers.trigger("customers", {
        betterSupabase,
        values: { organizationId: "organizationId" },
        topics: [{ topic: owner, values: { userId: "id", other: "id" } }],
      }),
    ).toThrow('"other" is not a placeholder of user:{userId}:customers');
  });

  it("fills placeholders from parent rows and sends a custom event and payload", () => {
    const tagged = defineTopic("org:{organizationSlug}:customer:{customerId}");

    const sql = tagged.trigger("customerTags", {
      betterSupabase,
      values: {
        customerId: "customerId",
        organizationSlug: {
          from: "organizations",
          select: "slug",
          via: {
            from: "customers",
            select: "organizationId",
            via: "customerId",
          },
        },
      },
      event: { insert: "tag_added", delete: "tag_removed" },
      payload: {
        tagId: "tagId",
        customerName: { from: "customers", via: "customerId", select: "name" },
        operation: { sql: "lower(tg_op) || ':' || {row}.tag_id" },
      },
    });

    expect(sql).toContain(
      `select j."organization_id", j."name" into lk_0 from "public"."customers" j where j."id" = rec."customer_id" limit 1;`,
    );
    expect(sql).toContain(
      `select j."slug" into lk_1 from "public"."organizations" j where j."id" = lk_0."organization_id" limit 1;`,
    );
    expect(sql).toContain(`'organizationSlug', (lk_1."slug")::text`);
    expect(sql).toContain(
      `body := jsonb_build_object('tagId', rec."tag_id", 'customerName', lk_0."name", 'operation', (lower(tg_op) || ':' || rec.tag_id));`,
    );
    expect(sql).toContain(
      `perform realtime.send(body, case tg_op when 'INSERT' then 'tag_added' when 'DELETE' then 'tag_removed' else tg_op end, 'org:' || (vals ->> 'organizationSlug') || ':customer:' || (vals ->> 'customerId'), true);`,
    );
    expect(
      customers.trigger("customers", {
        betterSupabase,
        values: { organizationId: "organizationId" },
        event: {},
      }),
    ).toContain("'values', vals), tg_op, 'organization:'");
    expect(
      defineTopic("public:{customerId}", { private: false }).trigger("notes", {
        betterSupabase,
        values: { customerId: "customerId" },
        event: "note",
        payload: { id: "id" },
      }),
    ).toContain("'note', 'public:' || (vals ->> 'customerId'), false);");
  });

  it("rejects lookups through unknown tables, keys and columns", () => {
    const tagged = defineTopic("org:{organizationId}");

    const lookup = (value: object) => () =>
      tagged.trigger("customerTags", {
        betterSupabase,
        // @ts-expect-error a lookup the types reject or the schema lacks
        values: { organizationId: value },
      });

    expect(
      lookup({ from: "nope", via: "customerId", select: "organizationId" }),
    ).toThrow('defineTopic: unknown table "nope" for {organizationId}');
    expect(
      lookup({ from: "customerTags", via: "customerId", select: "tagId" }),
    ).toThrow(/"customerTags" has no single-column primary key/);
    expect(
      lookup({ from: "customers", via: "customerId", select: "missing" }),
    ).toThrow(
      'defineTopic: no column for {organizationId} on "customers" ("missing")',
    );
    expect(
      lookup({ from: "customers", via: "missing", select: "organizationId" }),
    ).toThrow(/on "customerTags" \("missing"\)/);
    expect(
      tagged.trigger("customerTags", {
        betterSupabase,
        values: {
          organizationId: {
            from: "customerTags",
            key: "customerId",
            via: "customerId",
            select: "organizationId",
          },
        },
      }),
    ).toContain(`where j."customer_id" = rec."customer_id"`);
  });

  it("uses the given events and function schema", () => {
    const sql = customers.trigger("customers", {
      betterSupabase,
      values: { organizationId: "organizationId" },
      events: ["insert"],
      functionSchema: "private",
    });

    expect(sql).toContain(
      'create or replace function "private"."bs_broadcast_organization_customers_public_customers"()',
    );
    expect(sql).toContain(
      'create trigger "bs_broadcast_organization_customers" after insert on "public"."customers"',
    );
  });

  it("reads each lookup once per row, however many topics and payload keys use it", () => {
    const tenant = defineTopic("org:{organizationSlug}:tags");

    const perCustomer = defineTopic(
      "org:{organizationSlug}:customer:{customerId}",
    );

    const slug = {
      from: "organizations",
      select: "slug",
      via: { from: "customers", select: "organizationId", via: "customerId" },
    } as const;

    const sql = tenant.trigger("customerTags", {
      betterSupabase,
      values: { organizationSlug: slug },
      payload: { tagId: "tagId", organization: slug },
      topics: [
        {
          topic: perCustomer,
          values: { organizationSlug: slug, customerId: "customerId" },
        },
        { topic: tenant, values: { organizationSlug: slug } },
      ],
    });

    expect(sql).toMatchSnapshot();
    expect(sql.match(/from "public"\."customers" j/g)).toHaveLength(1);
    expect(sql.match(/from "public"\."organizations" j/g)).toHaveLength(1);
    expect(sql.match(/lk_1\."slug"/g)).toHaveLength(4);
    expect(sql).toContain(`'${LOOKUP_WARNING} for a delete on %.%`);
  });

  it("sends an update only when a when.changed column changed", () => {
    const updatesOnly = customers.trigger("customers", {
      betterSupabase,
      values: { organizationId: "organizationId" },
      events: ["update"],
      when: { changed: ["name", "organizationId"] },
    });

    expect(updatesOnly).toContain(
      `for each row when (old."name" is distinct from new."name" or old."organization_id" is distinct from new."organization_id") execute function`,
    );
    expect(updatesOnly).not.toContain("then return null; end if;");

    const all = customers.trigger("customers", {
      betterSupabase,
      values: { organizationId: "organizationId" },
      when: { changed: ["name"] },
    });

    expect(all).toContain(
      `  if tg_op = 'UPDATE' and not (old."name" is distinct from new."name") then return null; end if;`,
    );
    expect(all).toContain("  for each row execute function");

    expect(
      customers.trigger("public.customers", {
        events: ["update"],
        when: { changed: ["status"] },
      }),
    ).toContain(
      `for each row when (old."status" is distinct from new."status") execute function better_supabase.broadcast_topic(`,
    );
    expect(
      customers.trigger("public.customers", { when: { changed: ["status"] } }),
    ).toContain(
      `if tg_op = 'UPDATE' and not (old."status" is distinct from new."status") then return null; end if;`,
    );
  });

  it("rejects a when.changed the trigger can't apply", () => {
    expect(() =>
      customers.trigger("customers", {
        betterSupabase,
        values: { organizationId: "organizationId" },
        events: ["insert"],
        when: { changed: ["name"] },
      }),
    ).toThrow('when.changed filters updates, but events has no "update"');
    expect(() =>
      customers.trigger("customers", {
        betterSupabase,
        values: { organizationId: "organizationId" },
        when: { changed: [] },
      }),
    ).toThrow("when.changed lists no columns");
    expect(() =>
      customers.trigger("customers", {
        betterSupabase,
        values: { organizationId: "organizationId" },
        // @ts-expect-error not a column of customers
        when: { changed: ["missing"] },
      }),
    ).toThrow('no column for when.changed on "customers" ("missing")');
  });

  it("keeps triggerSql as a deprecated alias", () => {
    const options = { values: { organizationId: "organizationId" } } as const;

    // oxlint-disable-next-line typescript/no-deprecated -- tests the deprecated alias (1 finding)
    expect(customers.triggerSql(betterSupabase, "customers", options)).toBe(
      customers.trigger("customers", { ...options, betterSupabase }),
    );
  });
});

describe("rowChange", () => {
  it("maps broadcast_changes payloads to app casing", () => {
    const message = {
      event: "UPDATE",
      topic: "organization:o1:customers",
      payload: {
        schema: "public",
        table: "customers",
        operation: "UPDATE",
        record: { id: "c1", organization_id: "o1", name: "New" },
        old_record: { id: "c1", name: "Old" },
      },
    };

    expect(rowChange(betterSupabase, "customers", message)).toEqual({
      operation: "UPDATE",
      table: "customers",
      record: { id: "c1", organizationId: "o1", name: "New" },
      oldRecord: { id: "c1", name: "Old" },
    });
    expect(rowChange(betterSupabase, "notes", message)).toBeNull();
  });

  it("falls back to the event name and keeps null records", () => {
    expect(
      rowChange(betterSupabase, "customers", {
        event: "INSERT",
        topic: "organization:o1:customers",
        payload: { table: "customers", record: { id: "c1" }, old_record: null },
      }),
    ).toEqual({
      operation: "INSERT",
      table: "customers",
      record: { id: "c1" },
      oldRecord: null,
    });
    expect(
      rowChange(betterSupabase, "customers", {
        event: "x",
        topic: "t",
        payload: { table: "customers", operation: "DELETE", record: null },
      }),
    ).toMatchObject({ operation: "DELETE", record: null, oldRecord: null });
  });

  it("returns null for other schemas, unknown operations, empty payloads and unknown tables", () => {
    const at = (payload: unknown, event = "UPDATE") =>
      rowChange(betterSupabase, "customers", { event, topic: "t", payload });

    expect(at({ table: "customers", schema: "audit" })).toBeNull();
    expect(at({ table: "customers", operation: "TRUNCATE" })).toBeNull();
    expect(at({ table: "customers" }, "custom")).toBeNull();
    expect(at(null)).toBeNull();
    expect(
      // @ts-expect-error unknown table
      rowChange(betterSupabase, "nope", {
        event: "UPDATE",
        topic: "t",
        payload: {},
      }),
    ).toBeNull();
  });
});

describe("rowKeys", () => {
  it("reads the key payload and keeps only string values", () => {
    expect(
      rowKeys(betterSupabase, "customers", {
        event: "UPDATE",
        topic: "organization:o1:customers",
        payload: {
          operation: "UPDATE",
          schema: "public",
          table: "customers",
          id: "c1",
          values: { organizationId: "o1", other: 1 },
        },
      }),
    ).toEqual({
      operation: "UPDATE",
      schema: "public",
      table: "customers",
      id: "c1",
      values: { organizationId: "o1" },
    });
  });

  it("returns null for whole rows, other tables and other schemas", () => {
    const at = (payload: unknown) =>
      rowKeys(betterSupabase, "customers", { event: "x", topic: "t", payload });

    expect(
      at({ operation: "INSERT", table: "customers", record: {} }),
    ).toBeNull();
    expect(at({ operation: "INSERT", table: "notes", id: 1 })).toBeNull();
    expect(
      at({ operation: "INSERT", table: "customers", schema: "audit", id: 1 }),
    ).toBeNull();
    expect(at({ operation: "TRUNCATE", table: "customers", id: 1 })).toBeNull();
    expect(at(null)).toBeNull();
    expect(
      // @ts-expect-error unknown table
      rowKeys(betterSupabase, "nope", { event: "x", topic: "t", payload: {} }),
    ).toBeNull();
  });
});

describe("trigger", () => {
  it("calls broadcast_topic with the placeholders and their columns", () => {
    const quotes = defineTopic("organization:{organizationId}:quotes");
    expect(quotes.trigger("quotes", { event: "quote.changed" })).toBe(
      [
        "-- better-supabase: broadcast public.quotes changes to organization:{organizationId}:quotes",
        'drop trigger if exists "bs_broadcast_organization_quotes" on "public"."quotes";',
        'create trigger "bs_broadcast_organization_quotes" after insert or update or delete on "public"."quotes"',
        "  for each row execute function better_supabase.broadcast_topic('organization:{organizationId=organization_id}:quotes', 'quote.changed');",
        "",
      ].join("\n"),
    );
  });

  it("maps columns, limits the operations and passes 'false' for a public topic", () => {
    const board = defineTopic("board:{boardId}", { private: false });

    const sql = board.trigger("app.cards", {
      values: { boardId: "board" },
      events: ["insert", "delete"],
    });

    expect(sql).toContain(
      "after insert or delete on \"app\".\"cards\"\n  for each row execute function better_supabase.broadcast_topic('board:{boardId=board}', '', 'false');",
    );
  });

  it("passes the row payload only when asked", () => {
    const board = defineTopic("board:{board}");

    expect(board.trigger("cards", { payload: "row" })).toContain(
      "broadcast_topic('board:{board}', '', '', 'row');",
    );
    expect(board.trigger("cards", { payload: "keys" })).toContain(
      "broadcast_topic('board:{board}', '');",
    );
  });

  it("generates a function for fan-out, reading the key from the catalog", () => {
    const board = defineTopic("board:{boardId}");
    const owner = defineTopic("user:{userId}");

    const sql = board.trigger("cards", {
      topics: [{ topic: owner, values: { userId: "owner_id" } }],
    });

    expect(sql).toContain(
      'create or replace function "better_supabase"."bs_broadcast_board_public_cards"()',
    );
    expect(sql).toContain(
      `vals := jsonb_build_object('boardId', (rec."board_id")::text);`,
    );
    expect(sql).toContain(
      `vals := jsonb_build_object('userId', (rec."owner_id")::text);`,
    );
    expect(sql).toContain("where i.indrelid = tg_relid and i.indisprimary");
  });

  it("looks up values by database names without betterSupabase", () => {
    const org = defineTopic("org:{orgId}:inbox");
    const thread = defineTopic("thread:{threadId}");

    const sql = org.trigger("inbox.messages", {
      values: {
        orgId: { from: "inbox.threads", via: "thread_id", select: "org_id" },
      },
      event: { insert: "created", delete: "deleted" },
      payload: {
        operation: { sql: "lower(tg_op)" },
        thread_id: "thread_id",
        record_id: "id",
        owner: {
          from: "users",
          key: "user_id",
          via: { from: "inbox.threads", via: "thread_id", select: "owner" },
          select: "email",
        },
      },
      topics: [{ topic: thread, values: { threadId: "thread_id" } }],
    });

    expect(sql).toContain(
      'create or replace function "better_supabase"."bs_broadcast_org_inbox_inbox_messages"()',
    );
    expect(sql).toContain(
      `select j."org_id", j."owner" into lk_0 from "inbox"."threads" j where j."id" = rec."thread_id" limit 1;`,
    );
    expect(sql).toContain(
      `vals := jsonb_build_object('orgId', (lk_0."org_id")::text);`,
    );
    expect(sql).toContain(
      `vals := jsonb_build_object('threadId', (rec."thread_id")::text);`,
    );
    expect(sql).toContain(
      `select j."email" into lk_1 from "public"."users" j where j."user_id" = lk_0."owner" limit 1;`,
    );
    expect(sql).toContain(
      `body := jsonb_build_object('operation', (lower(tg_op)), 'thread_id', rec."thread_id", 'record_id', rec."id", 'owner', lk_1."email");`,
    );
    expect(sql).toContain(
      `perform realtime.send(body, case tg_op when 'INSERT' then 'created' when 'DELETE' then 'deleted' else tg_op end, 'org:' || (vals ->> 'orgId') || ':inbox', true);`,
    );
    expect(sql).not.toContain("broadcast_topic(");
  });

  it("names the function after the schema, so tables in two schemas don't collide", () => {
    const board = defineTopic("board:{boardId}");
    const owner = defineTopic("user:{userId}");

    const options = {
      topics: [{ topic: owner, values: { userId: "owner_id" } }],
    };

    const publicSql = board.trigger("public.items", options);
    const crmSql = board.trigger("crm.items", options);

    expect(publicSql).toContain(
      '"better_supabase"."bs_broadcast_board_public_items"()',
    );
    expect(crmSql).toContain(
      '"better_supabase"."bs_broadcast_board_crm_items"()',
    );
    expect(publicSql).toContain('create trigger "bs_broadcast_board"');
    expect(crmSql).toContain('create trigger "bs_broadcast_board"');
  });

  it("rejects a value for no placeholder and a column with braces", () => {
    const board = defineTopic("board:{boardId}");
    expect(() =>
      // @ts-expect-error not a placeholder
      board.trigger("cards", { values: { cardId: "id" } }),
    ).toThrow('"cardId" is not a placeholder of board:{boardId}');
    expect(() =>
      board.trigger("cards", { values: { boardId: "a}b" } }),
    ).toThrow("the column for {boardId} can't contain braces or =");
  });
});
