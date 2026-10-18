import type { StandardSchemaV1 } from "@standard-schema/spec";

import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../../src/core/block-transport.ts";

import {
  createNotifications,
  watcherHandler,
  watcherSink,
} from "../../../src/blocks/notifications/index.ts";

const anything: StandardSchemaV1<Record<string, unknown>> = {
  "~standard": {
    version: 1,
    vendor: "test",
    validate: (value) =>
      typeof value === "object" && value !== null
        ? { value: { ...value } }
        : { issues: [{ message: "an object" }] },
  },
};

const types = { "comment.posted": anything, "reminder.due": anything };

function recording() {
  const sent: Record<string, unknown>[] = [];

  const transport: BlockTransport = {
    async call(_schema, fn, args) {
      if (
        fn === "send_notification" &&
        typeof args["notification"] === "object"
      ) {
        sent.push({ ...(args["notification"] as Record<string, unknown>) });
      }

      if (fn === "send_notifications" && Array.isArray(args["events"])) {
        const batch = args["events"] as Record<string, unknown>[];
        sent.push(...batch.map((item) => ({ ...item })));

        return batch.map(() => ({
          notification: { id: "n1", recipients: [] },
        }));
      }

      return { id: "n1", recipients: [] };
    },
  };

  return { notifications: createNotifications({ transport, types }), sent };
}

const event = (
  type: string,
  data: unknown,
  extra: Record<string, unknown> = {},
) => ({
  specversion: "1.0" as const,
  id: `id-${type}`,
  source: "/better-supabase/outbox",
  type: `dev.better-supabase.${type}`,
  data,
  ...extra,
});

describe("watcherSink", () => {
  it("notifies a subject's watchers without the actor, keyed by the event", async () => {
    const { notifications, sent } = recording();

    const sink = watcherSink(notifications, {
      types: { "comment.created": "comment.posted" },
    });

    await sink.send([
      event("comment.created", {
        commentId: "c1",
        organizationId: "org_1",
        subjectType: "task",
        subjectId: "42",
        authorId: "u1",
      }),
    ]);
    expect(sent).toEqual([
      expect.objectContaining({
        type: "comment.posted",
        tenant: "org_1",
        subject_type: "task",
        subject_id: "42",
        recipients: [],
        activity: "all",
        key: "watch:id-comment.created",
        actor: "u1",
      }),
    ]);
  });

  it("skips unmapped events and events without a subject or tenant", async () => {
    const { notifications, sent } = recording();

    const sink = watcherSink(notifications, {
      types: {
        "comment.created": "comment.posted",
        "tag.created": "comment.posted",
      },
    });

    await sink.send([
      event("status.changed", {
        organizationId: "org_1",
        subjectType: "deal",
        subjectId: "d1",
      }),
      event("tag.created", { organizationId: "org_1", id: "t1" }),
      event("comment.created", { subjectType: "task", subjectId: "42" }),
      event("comment.created", "not an object"),
    ]);
    expect(sent).toEqual([]);
  });

  it("takes the tenant from partitionkey and applies a rule", async () => {
    const { notifications, sent } = recording();

    const sink = watcherSink(notifications, {
      types: {
        "reminder.sent": {
          type: "reminder.due",
          activity: "participating",
          recipients: (data) =>
            typeof data["userId"] === "string" ? [data["userId"]] : [],
          data: (_event, data) => ({ reminderId: data["id"] }),
          summary: (data) =>
            `Reminder for ${data.subjectType} ${data.subjectId}`,
        },
      },
    });

    await sink.send([
      event(
        "reminder.sent",
        {
          organizationId: null,
          id: "r1",
          subjectType: "task",
          subjectId: "7",
          userId: "u2",
        },
        { partitionkey: "org_2" },
      ),
    ]);
    expect(sent[0]).toMatchObject({
      type: "reminder.due",
      tenant: "org_2",
      recipients: ["u2"],
      activity: "participating",
      data: { reminderId: "r1" },
      summary: "Reminder for task 7",
    });
  });
});

describe("watcherHandler", () => {
  const row = (type: string, payload: unknown, actorId: string | null) => ({
    position: 1,
    id: `id-${type}`,
    type,
    payload,
    source: null,
    subject: null,
    tenant: "org_1",
    key: null,
    actorId,
    createdAt: Temporal.Instant.from("2026-10-13T09:00:00Z"),
  });

  it("leaves out the actor the outbox row names, for any subject event", async () => {
    const { notifications, sent } = recording();

    const handle = watcherHandler(notifications, {
      types: {
        "subject.tagged": "comment.posted",
        "status.changed": "comment.posted",
      },
    });

    await handle([
      row(
        "subject.tagged",
        { subjectType: "deal", subjectId: "d1", tagId: "t1" },
        "u1",
      ),
      row(
        "status.changed",
        { subjectType: "deal", subjectId: "d1", actorId: "u3" },
        "u2",
      ),
      row("status.changed", { subjectType: "deal", subjectId: "d2" }, null),
    ]);
    expect(
      sent.map((n) => [n["key"], n["tenant"], n["actor"] ?? null]),
    ).toEqual([
      ["watch:id-subject.tagged", "org_1", "u1"],
      ["watch:id-status.changed", "org_1", "u3"],
      ["watch:id-status.changed", "org_1", null],
    ]);
  });
});
