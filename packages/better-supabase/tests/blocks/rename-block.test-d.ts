import { describe, expectTypeOf, it } from "vitest";

import type {
  RenamedClient,
  RenamedEvents,
  RenamedType,
  RenameKey,
  RenamesOf,
} from "../../src/blocks/rename-block.ts";
import type {
  WorkItem,
  WorkItems,
} from "../../src/blocks/work-items/work-items.ts";
import type { AsyncResult } from "../../src/core/result.ts";

import { renameBlock } from "../../src/blocks/rename-block.ts";
import { workItemsBlock } from "../../src/blocks/work-items/manifest.ts";

const NAMES = {
  entities: [
    {
      from: { singular: "work_item", plural: "work_items" },
      to: { singular: "task", plural: "tasks" },
    },
    {
      from: { singular: "project", plural: "projects" },
      to: { singular: "initiative", plural: "initiatives" },
    },
  ],
} as const;

type R = RenamesOf<typeof NAMES>;

describe("RenameKey", () => {
  it("renames snake, camel and pascal forms on word bounds", () => {
    expectTypeOf<
      RenameKey<"list_work_items", R>
    >().toEqualTypeOf<"list_tasks">();
    expectTypeOf<RenameKey<"workItemIds", R>>().toEqualTypeOf<"taskIds">();
    expectTypeOf<
      RenameKey<"saveProject", R>
    >().toEqualTypeOf<"saveInitiative">();
    expectTypeOf<
      RenameKey<"work_item.created", R>
    >().toEqualTypeOf<"task.created">();
    expectTypeOf<
      RenameKey<"projectionId", R>
    >().toEqualTypeOf<"projectionId">();
  });

  it("never renames a new name again", () => {
    type Grown = readonly [
      {
        readonly from: { readonly singular: "deal"; readonly plural: "deals" };
        readonly to: {
          readonly singular: "big_deal";
          readonly plural: "big_deals";
        };
      },
    ];

    expectTypeOf<RenameKey<"dealId", Grown>>().toEqualTypeOf<"bigDealId">();
    expectTypeOf<RenameKey<"deals", Grown>>().toEqualTypeOf<"big_deals">();
  });
});

describe("RenamedType", () => {
  it("renames row keys and leaves extra fields alone", () => {
    type Task = RenamedType<WorkItem<{ readonly project_code: string }>, R>;

    expectTypeOf<Task["initiativeId"]>().toEqualTypeOf<string | undefined>();
    expectTypeOf<Task["fields"]>().toEqualTypeOf<
      WorkItem<{ readonly project_code: string }>["fields"]
    >();
    expectTypeOf<Task>().not.toHaveProperty("projectId");
  });

  it("is the type itself without renames", () => {
    expectTypeOf<RenamedType<WorkItem, []>>().toEqualTypeOf<WorkItem>();
  });
});

describe("RenamedClient", () => {
  type Tasks = RenamedClient<WorkItems, R>;

  it("renames methods, arguments and results", () => {
    expectTypeOf<Tasks>().toHaveProperty("saveInitiative");
    expectTypeOf<Tasks>().not.toHaveProperty("saveProject");
    expectTypeOf<Parameters<Tasks["list"]>[1]>().toExtend<
      { readonly initiativeId?: string } | undefined
    >();
    expectTypeOf<ReturnType<Tasks["list"]>>().toExtend<
      AsyncResult<readonly { readonly initiativeId?: string }[]>
    >();
  });

  it("renames the column a change names", () => {
    type Change = Parameters<Tasks["update"]>[0][number];

    expectTypeOf<"initiativeId">().toExtend<Change["field"]>();
    expectTypeOf<Change>().toHaveProperty("taskId");
  });
});

describe("renameBlock", () => {
  const tasks = renameBlock(workItemsBlock, NAMES);

  it("renames the event map", () => {
    expectTypeOf<
      keyof RenamedEvents<
        { "work_item.closed": { readonly workItemId: string } },
        R
      >
    >().toEqualTypeOf<"task.closed">();
    expectTypeOf(tasks.events["~map"]).toExtend<
      { readonly "task.created": unknown } | undefined
    >();
  });

  it("keys hooks by the renamed methods", () => {
    type Options = Parameters<NonNullable<typeof tasks.create>>[0];

    expectTypeOf<NonNullable<Options["hooks"]>>().toHaveProperty(
      "saveInitiative",
    );
  });

  it("keeps the block when nothing is renamed", () => {
    expectTypeOf(renameBlock(workItemsBlock, undefined)).toEqualTypeOf(
      workItemsBlock,
    );
  });
});
