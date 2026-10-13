import type { StandardSchemaV1 } from "@standard-schema/spec";

import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../../src/core/block-transport.ts";

import {
  createNotifications,
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
