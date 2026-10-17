import type { StandardSchemaV1 } from "@standard-schema/spec";

import { describe, expect, it, vi } from "vitest";

import type { SubscriberPolicy } from "../../src/core/contracts/authorization-hooks.ts";
import type { RealtimeClient } from "../../src/realtime/index.ts";

import { defineAuthorizationHooks } from "../../src/core/contracts/authorization-hooks.ts";
import { defineTopic } from "../../src/realtime/index.ts";
import { allowedSubscribers } from "../../src/realtime/subscribers.ts";

const FUNCTIONS = {
  idsWith: "app.ids_{scope}({permission})",
  isPlatform: "app.is_platform({permission})",
  permitted:
    "app.permitted({permission}, {resource}, {id}, {tenant}, '{scope}')",
};

const topicSegment = (index: number) =>
  `split_part((select realtime.topic()), ':', ${String(index)})`;

const title: StandardSchemaV1<unknown, { title: string }> = {
  "~standard": {
    version: 1,
    vendor: "test",
    validate: (value) =>
      typeof (value as { title?: unknown } | null)?.title === "string"
        ? { value: { title: (value as { title: string }).title } }
        : { issues: [{ message: "title is required" }] },
  },
};

describe("defineTopic({ permission })", () => {
  const posts = defineTopic("organization:{organizationId}:posts:{postId}", {
    permission: "posts.read",
  });

  it("checks the access contract on the tenant segment without a provider", () => {
    const sql = posts.sql();
    expect(sql).toContain(
      `and ${topicSegment(2)} in (select t::text from better_supabase.tenant_ids_with('posts.read') t)`,
    );
    expect(sql).toContain(`${topicSegment(2)} = (coalesce(`);
  });

  it("fills the provider's permitted template with the instance id from the topic", () => {
    expect(posts.sql({ functions: FUNCTIONS })).toContain(
      `and coalesce((app.permitted('posts.read', 'posts', ${topicSegment(4)}, ${topicSegment(2)}, 'tenant')), false)`,
    );
  });

  it("takes the param, resource and scope from the object form", () => {
    const comments = defineTopic(
      "organization:{organizationId}:posts:{postId}:comments",
      {
        permission: {
          key: "comments.read",
          param: "postId",
          resource: "post",
          scope: "project",
        },
      },
    );

    expect(comments.sql({ functions: FUNCTIONS })).toContain(
      `app.permitted('comments.read', 'post', ${topicSegment(4)}, ${topicSegment(2)}, 'project')`,
    );
  });

  it("passes a null tenant to permitted for a topic without one", () => {
    const doc = defineTopic("doc:{docId}", {
      permission: "docs.read",
    });

    expect(doc.sql({ functions: FUNCTIONS })).toContain(
      `app.permitted('docs.read', 'docs', ${topicSegment(2)}, null::text, 'tenant')`,
    );
    expect(() => doc.sql()).toThrow(
      /`permitted` template, or a tenant segment/,
    );
  });

  it("guards the permission at definition and render time", () => {
    expect(() =>
      defineTopic("organization:{organizationId}:posts:{postId}", {
        permission: "",
      }),
    ).toThrow(/permission is empty/);
    expect(() =>
      defineTopic("announcements", { permission: "posts.read" }),
    ).toThrow(/placeholder for the instance id/);
    expect(() =>
      defineTopic("organization:{organizationId}:posts:{postId}", {
        permission: { key: "posts.read", param: "missing" },
      }),
    ).toThrow(/needs \{missing\} as a whole segment/);
    expect(() =>
      defineTopic("organization:{organizationId}:posts:{postId}", {
        permission: { key: "posts.read", scope: "org; drop" },
      }).sql({ functions: FUNCTIONS }),
    ).toThrow(/invalid permission scope/);
  });

  it("leaves topics without a permission unchanged", () => {
    const sql = defineTopic("organization:{organizationId}:feed").sql({
      functions: FUNCTIONS,
    });

    expect(sql).not.toContain("app.permitted");
    expect(sql).not.toContain("tenant_ids_with");
  });
});

describe("allowedSubscribers", () => {
  const event = {
    type: "post.created",
    tenant: "o1",
    actorId: "u0",
    payload: {},
    subject: "post/1",
  };

  const people = [
    { principal: "u1" },
    { principal: "u2", kind: "user" as const },
    { principal: "svc", kind: "service" as const },
  ];

  it("allows everyone without a policy or without subscribers", async () => {
    expect(await allowedSubscribers(undefined, event, people)).toEqual({
      ok: true,
      allowed: people,
    });
    const policy = vi.fn(() => []);
    expect(
      await allowedSubscribers(policy as SubscriberPolicy, event, []),
    ).toEqual({
      ok: true,
      allowed: [],
    });
    expect(policy).not.toHaveBeenCalled();
  });

  it("keeps the passed subscribers the policy returns, matching kind and principal", async () => {
    const leaky = async () => [
      { principal: "u1", kind: "user" },
      { principal: "svc", kind: "user" },
      { principal: "stranger" },
      "junk",
    ];

    const result = await allowedSubscribers(
      leaky as unknown as SubscriberPolicy,
      event,
      people,
    );

    expect(result).toEqual({ ok: true, allowed: [people[0]] });
  });

  it("reports a throw, a rejection or a result that is not a list", async () => {
    const boom = new Error("down");
    expect(
      await allowedSubscribers(
        () => {
          throw boom;
        },
        event,
        people,
      ),
    ).toEqual({ ok: false, cause: boom });
    expect(
      (await allowedSubscribers(() => Promise.reject(boom), event, people)).ok,
    ).toBe(false);
    expect(
      // @ts-expect-error -- a broken policy
      (await allowedSubscribers(() => ({}), event, people)).ok,
    ).toBe(false);
  });
});

describe("topic.fanOut", () => {
  function fakeClient(fail?: string) {
    const sent: { topic: string; event: string; payload: unknown }[] = [];

    const client = {
      getChannels: () => [],
      channel: (topic: string) => ({
        topic: `realtime:${topic}`,
        httpSend: async (event: string, payload: unknown) => {
          if (topic.endsWith(`:${fail ?? "-"}`)) {
            return { success: false, status: 500, error: "down" };
          }

          sent.push({ topic, event, payload });

          return { success: true };
        },
      }),
      removeChannel: async () => "ok" as const,
      realtime: { setAuth: async () => undefined },
    };

    return { client: client as unknown as RealtimeClient, sent };
  }

  const source = {
    type: "post.created",
    tenant: "o1",
    actorId: "u0",
    payload: { postId: "p1" },
    subject: "post/p1",
  };

  const subscribers = [{ principal: "u1" }, { principal: "u2" }];

  const inbox = (subscriberPolicy?: SubscriberPolicy) =>
    defineTopic("inbox:{userId}", {
      events: { created: title },
      ...(subscriberPolicy === undefined
        ? {}
        : { subscribers: subscriberPolicy }),
    });

  it("sends to each subscriber the topic's policy keeps", async () => {
    const policy = vi.fn<SubscriberPolicy>((_event, all) =>
      all.filter((subscriber) => subscriber.principal === "u2"),
    );

    const topicPolicy = policy as unknown as SubscriberPolicy;
    const { client, sent } = fakeClient();

    const result = await inbox(topicPolicy)
      .fanOut(client, {
        subscribers,
        values: (subscriber) => ({ userId: subscriber.principal }),
        event: "created",
        payload: { title: "New post" },
        source,
      })
      .orThrow();

    expect(policy).toHaveBeenCalledWith(source, subscribers);
    expect(result).toEqual({
      sent: [subscribers[1]],
      skipped: [subscribers[0]],
      failed: [],
    });
    expect(sent).toEqual([
      { topic: "inbox:u2", event: "created", payload: { title: "New post" } },
    ]);
  });

  it("prefers the call's policy, then falls back to the server's delivery subscribers", async () => {
    const { client, sent } = fakeClient();
    const topic = inbox(() => []);
    await topic
      .fanOut(client, {
        subscribers,
        values: (subscriber) => ({ userId: subscriber.principal }),
        event: "created",
        payload: { title: "Hi" },
        source,
        policy: (_event, all) => all,
      })
      .orThrow();
    expect(sent).toHaveLength(2);

    const server = {
      authorization: defineAuthorizationHooks({
        apiVersion: 1,
        name: "test",
        delivery: {
          subscribers: (() => [
            { principal: "u1" },
          ]) as unknown as SubscriberPolicy,
        },
      }),
    };

    const result = await inbox()
      .fanOut(client, {
        subscribers,
        values: (subscriber) => ({ userId: subscriber.principal }),
        event: "created",
        payload: { title: "Hi" },
        source,
        server,
      })
      .orThrow();

    expect(result.sent).toEqual([subscribers[0]]);
  });

  it("sends to no one when the policy throws", async () => {
    const { client, sent } = fakeClient();

    const result = await inbox(() => {
      throw new Error("down");
    }).fanOut(client, {
      subscribers,
      values: (subscriber) => ({ userId: subscriber.principal }),
      event: "created",
      payload: { title: "Hi" },
      source,
    });

    expect(result.ok).toBe(false);
    expect(result.error).toMatchObject({
      kind: "forbidden",
      hint: "REALTIME_SUBSCRIBER_POLICY_FAILED",
    });
    expect(sent).toEqual([]);
  });

  it("refuses an event with a subject under hooks without a policy", async () => {
    const { client, sent } = fakeClient();

    const server = {
      authorization: defineAuthorizationHooks({ apiVersion: 1, name: "test" }),
    };

    const result = await inbox().fanOut(client, {
      subscribers,
      values: (subscriber) => ({ userId: subscriber.principal }),
      event: "created",
      payload: { title: "Hi" },
      source,
      server,
    });

    expect(!result.ok && result.error.hint).toBe(
      "REALTIME_SUBSCRIBER_POLICY_REQUIRED",
    );
    expect(sent).toEqual([]);

    const tenantWide = await inbox()
      .fanOut(client, {
        subscribers,
        values: (subscriber) => ({ userId: subscriber.principal }),
        event: "created",
        payload: { title: "Hi" },
        source: { ...source, subject: null },
        server,
      })
      .orThrow();

    expect(tenantWide.sent).toEqual(subscribers);
  });

  it("collects failed sends and keeps going", async () => {
    const { client, sent } = fakeClient("u1");

    const result = await inbox()
      .fanOut(client, {
        subscribers,
        values: (subscriber) => ({ userId: subscriber.principal }),
        event: "created",
        payload: { title: "Hi" },
        source,
      })
      .orThrow();

    expect(result.sent).toEqual([subscribers[1]]);
    expect(result.failed).toHaveLength(1);
    expect(result.failed[0]?.subscriber).toBe(subscribers[0]);
    expect(sent.map((entry) => entry.topic)).toEqual(["inbox:u2"]);
  });
});
