import { describe, expect, it } from "vitest";

import { dealInputSchema } from "../../src/blocks/deals/schemas.ts";
import { renameBlock } from "../../src/blocks/rename-block.ts";
import { workItemsBlock } from "../../src/blocks/work-items/manifest.ts";
import {
  workItemChangeSchema,
  workItemInputSchema,
  workItemListFilterSchema,
} from "../../src/blocks/work-items/schemas.ts";

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
    expect(workItemsBlock.schemas["work_item"]?.change).toBe(
      workItemChangeSchema,
    );
  });

  it("renames the schemas of a renamed block", async () => {
    const tasks = renameBlock(workItemsBlock, names);
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
