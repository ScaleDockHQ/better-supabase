import { describe, expect, it } from "vitest";

import { activitiesBlock } from "../../src/blocks/activities/manifest.ts";
import { engagementInputSchema } from "../../src/blocks/activities/schemas.ts";
import { attachmentsBlock } from "../../src/blocks/attachments/manifest.ts";
import { calendarBlock } from "../../src/blocks/calendar/manifest.ts";
import { calendarEventInputSchema } from "../../src/blocks/calendar/schemas.ts";
import { commentsBlock } from "../../src/blocks/comments/manifest.ts";
import { commentInputSchema } from "../../src/blocks/comments/schemas.ts";
import { dealInputSchema } from "../../src/blocks/deals/schemas.ts";
import { renameBlock } from "../../src/blocks/rename-block.ts";
import { tasksBlock } from "../../src/blocks/tasks/manifest.ts";
import {
  workItemChangeSchema,
  workItemInputSchema,
  workItemListFilterSchema,
} from "../../src/blocks/tasks/schemas.ts";

const names = {
  entities: [
    {
      from: { singular: "work_item", plural: "work_items" },
      to: { singular: "task", plural: "tasks" },
    },
  ],
} as const;

const ID = "0f8e2b4c-1d3a-4e5f-8a9b-0c1d2e3f4a5b";

describe("entity schemas", () => {
  it("checks a deal's close date and amounts as Temporal and Money values", async () => {
    const closeOn = Temporal.PlainDate.from("2026-12-31");
    const amount = { amount: 125_000n, currency: "EUR" };

    const valid = await dealInputSchema["~standard"].validate({
      name: "Acme renewal",
      closeOn,
      amount,
    });

    const invalid = await dealInputSchema["~standard"].validate({
      name: "Acme renewal",
      closeOn: "2026-12-31",
      amount: { amount: 125_000, currency: "EUR" },
    });

    expect(valid).toEqual({ value: { name: "Acme renewal", closeOn, amount } });
    expect(invalid.issues?.map((issue) => issue.path)).toEqual([
      ["closeOn"],
      ["amount", "amount"],
    ]);
  });

  it("validates a work item input with the bounds the SQL checks", async () => {
    const valid = await workItemInputSchema["~standard"].validate({
      title: "Ship it",
      priority: 2,
      extra: true,
    });

    const invalid = await workItemInputSchema["~standard"].validate({
      title: "",
      priority: 7,
    });

    expect(valid).toEqual({ value: { title: "Ship it", priority: 2 } });
    expect(invalid.issues?.map((issue) => issue.path)).toEqual([
      ["title"],
      ["priority"],
    ]);
  });

  it("converts to JSON Schema", () => {
    const schema = workItemListFilterSchema["~standard"].jsonSchema.input({
      target: "draft-2020-12",
    });

    expect(schema).toMatchObject({
      title: "WorkItemListOptions",
      properties: {
        states: { type: "array", items: { enum: expect.any(Array) } },
        limit: { type: "integer", minimum: 1 },
      },
    });
  });

  it("puts the schemas on the block's manifest", () => {
    expect(tasksBlock.schemas["work_item"]?.change).toBe(workItemChangeSchema);
  });

  it("validates the collaboration blocks' inputs", async () => {
    const comment = await commentInputSchema["~standard"].validate({
      body: 42,
      mentionIds: [ID],
    });

    const engagement = await engagementInputSchema["~standard"].validate({
      type: "call",
      title: "x".repeat(501),
      dueAt: null,
    });

    const event = await calendarEventInputSchema["~standard"].validate({
      status: "maybe",
      rrule: null,
    });

    expect(comment.issues?.map((issue) => issue.path)).toEqual([["body"]]);
    expect(engagement.issues?.map((issue) => issue.path)).toEqual([["title"]]);
    expect(event.issues?.map((issue) => issue.path)).toEqual([["status"]]);
    expect(commentsBlock.schemas).toEqual({});
    expect(Object.keys(attachmentsBlock.schemas)).toEqual(["attachment"]);
    expect(Object.keys(activitiesBlock.schemas)).toEqual(["engagement"]);
    expect(Object.keys(calendarBlock.schemas)).toEqual(["calendar_event"]);
  });

  it("renames the schemas of a renamed block", async () => {
    const tasks = renameBlock(tasksBlock, names);
    const change = tasks.schemas["task"]?.change;

    const valid = await change?.["~standard"].validate({
      taskId: ID,
      field: "projectId",
      value: null,
    });

    const invalid = await change?.["~standard"].validate({ field: "title" });

    const json = change?.["~standard"].jsonSchema.input({
      target: "draft-2020-12",
    });

    expect(valid).toEqual({
      value: { taskId: ID, field: "projectId", value: null },
    });
    expect(invalid?.issues?.map((issue) => issue.path)).toEqual([["taskId"]]);
    expect(json).toMatchObject({
      title: "TaskChange",
      properties: { taskId: { type: "string" } },
      required: ["taskId", "field", "value"],
    });
  });
});
