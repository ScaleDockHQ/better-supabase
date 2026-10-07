import type { StandardSchemaV1 } from "@standard-schema/spec";

import { describe, expect, it, vi } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { DbException } from "../../src/core/errors.ts";
import {
  defineTopic,
  type RealtimeClient,
  rowChange,
} from "../../src/realtime/index.ts";
import { schema, topics } from "../fixtures/generated-camel.ts";

const betterSupabase = defineSupabase(schema);

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
  const removed: unknown[] = [];
  const open: unknown[] = [];
  let report: ((status: string, error?: Error) => void) | undefined;
  const channel = {
    topic: "",
    on: (_type: string, _filter: unknown, listener: Listener) => {
      listeners.push(listener);
      return channel;
    },
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
      if (!open.includes(channel)) channel.topic = `realtime:${topic}`;
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
    for (const listener of listeners) listener({ event, payload });
  };
  return {
    client: client as unknown as RealtimeClient,
    raw: client,
    channel,
    emit,
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

  it("compiles PermDock receive and send policies", () => {
    const board = defineTopic("organization:{organizationId}:board", {
      permdock: {
        receive: "board.read",
        send: "board.write",
        scope: "organization",
      },
    }).sql();
    const ids = (key: string) =>
      `split_part((select realtime.topic()), ':', 2) in (select t.id::text from "permdock"."permitted_organization_ids"('${key}') as t(id))`;
    expect(board).toContain(
      `for select to authenticated\n  using (\n    (select realtime.topic()) ~ '^organization:[^:]+:board$'\n    and realtime.messages.extension in ('broadcast')\n    and ${ids("board.read")}\n  );`,
    );
    expect(board).toContain(`for insert to authenticated\n  with check (`);
    expect(board).toContain(ids("board.write"));
    expect(board).not.toContain("tenant_id");
    expect(board).not.toContain("service_role");

    const receiveOnly = defineTopic("announcements", {
      permdock: { receive: "announcements.read", scope: "global" },
    }).sql();
    expect(receiveOnly).toContain(
      `(select "permdock".permdock_has('announcements.read'))`,
    );
    expect(receiveOnly).not.toContain("for insert");
    expect(() =>
      defineTopic("organization:{organizationId}", {
        permdock: { receive: "x.read#1", scope: "organization" },
      }),
    ).toThrow(/splits by row condition/);
    const catalog = {
      permissions: [
        { key: "board.write", rowConditions: true },
        { key: "board.read", rowConditions: false },
        { key: "board.watch" },
      ],
    };
    expect(() =>
      defineTopic("organization:{organizationId}:board", {
        permdock: { receive: "board.watch", scope: "organization" },
        catalog,
      }),
    ).toThrow(/"board\.watch" has no rowConditions flag/);
    expect(() =>
      defineTopic("organization:{organizationId}:board", {
        permdock: { receive: "board.other", scope: "organization" },
        catalog,
      }),
    ).toThrow(/"board\.other" is not in PermDock's catalog/);
    expect(() =>
      defineTopic("organization:{organizationId}:board", {
        permdock: {
          receive: "board.read",
          send: "board.write",
          scope: "organization",
        },
        catalog,
      }),
    ).toThrow(/"board\.write" has row conditions/);
    expect(
      defineTopic("organization:{organizationId}:board", {
        permdock: { receive: "board.read", scope: "organization" },
        catalog,
      }).sql(),
    ).toContain("board.read");
  });

  it("generates a row-change trigger with database column names", () => {
    const sql = defineTopic(topics.customers).triggerSql(
      betterSupabase,
      "customers",
      {
        values: { organizationId: "organizationId" },
      },
    );
    expect(sql).toContain('create schema if not exists "better_supabase";');
    expect(sql).toContain(
      'create or replace function "better_supabase"."bs_broadcast_organization_customers_customers"()',
    );
    expect(sql).toContain(
      "'organization:' || rec.\"organization_id\"::text || ':customers',",
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
    const { client, raw } = fakeClient();
    const subscription = room.subscribe(
      client,
      { roomId: "r1" },
      {},
      { self: true },
    );
    await subscription.ready;
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
        permdock: { receive: "a.read", scope: "organization" },
      }),
    ).toThrow(/the PermDock check needs \{organizationId\}/);
  });

  it("drops the tenant and owner checks when disabled", () => {
    const sql = defineTopic("organization:{organizationId}:inbox:{userId}", {
      tenant: false,
      owner: false,
    }).sql();
    expect(sql).not.toContain("split_part");
  });

  it("uses an explicit PermDock segment and the default organizationId without a tenant", () => {
    expect(
      defineTopic("x:{a}:{organizationId}", {
        tenant: false,
        permdock: { receive: "a.read", scope: "organization" },
      }).sql(),
    ).toContain("split_part((select realtime.topic()), ':', 3) in");
    expect(
      defineTopic("x:{a}:{b}", {
        permdock: { receive: "a.read", scope: "organization", segment: 2 },
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

describe("triggerSql", () => {
  const customers = defineTopic(topics.customers);

  it("rejects unknown tables and unmapped parameters", () => {
    expect(() =>
      // @ts-expect-error unknown table
      customers.triggerSql(betterSupabase, "nope", {
        values: { organizationId: "id" },
      }),
    ).toThrow('defineTopic: unknown table "nope"');
    expect(() =>
      customers.triggerSql(betterSupabase, "customers", {
        // @ts-expect-error missing value
        values: {},
      }),
    ).toThrow('defineTopic: no column for {organizationId} on "customers"');
    expect(() =>
      customers.triggerSql(betterSupabase, "customers", {
        // @ts-expect-error unknown column
        values: { organizationId: "missing" },
      }),
    ).toThrow('defineTopic: no column for {organizationId} on "customers"');
  });

  it("uses the given events and function schema", () => {
    const sql = customers.triggerSql(betterSupabase, "customers", {
      values: { organizationId: "organizationId" },
      events: ["insert"],
      functionSchema: "private",
    });
    expect(sql).toContain(
      'create or replace function "private"."bs_broadcast_organization_customers_customers"()',
    );
    expect(sql).toContain(
      'create trigger "bs_broadcast_organization_customers" after insert on "public"."customers"',
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
