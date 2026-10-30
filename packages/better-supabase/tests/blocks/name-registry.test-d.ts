import { describe, expectTypeOf, it } from "vitest";

import type {
  ActionsOf,
  BlockNameRegistry,
  FunctionsOf,
  TablesOf,
} from "../../src/blocks/name-registry.ts";
import type { BlockOptionsRegistry } from "../../src/blocks/options-registry.ts";
import type { BlocksConfig } from "../../src/config/blocks.ts";

describe("BlockNameRegistry", () => {
  it("has a names for every module with options", () => {
    expectTypeOf<
      Exclude<keyof BlockOptionsRegistry, keyof BlockNameRegistry>
    >().toBeNever();
  });

  it("lists a module's tables, functions and actions", () => {
    expectTypeOf<"items">().toExtend<TablesOf<"tasks">>();
    expectTypeOf<"list_tasks">().toExtend<FunctionsOf<"tasks">>();
    expectTypeOf<"read">().toExtend<ActionsOf<"tasks">>();
  });
});

describe("BlocksConfig", () => {
  it("accepts the names a module declares", () => {
    const config = {
      tasks: {
        tables: { items: "public.tasks" },
        columns: { items: { title: "name" } },
        functions: { list_tasks: "list_tasks" },
        permissions: { read: "tasks.read" },
        hooks: { functions: { after_task_create: "app.on_task" } },
      },
    } satisfies BlocksConfig;

    expectTypeOf(config).toExtend<BlocksConfig>();
  });

  it("rejects names a module doesn't declare", () => {
    const tables: BlocksConfig = {
      tasks: {
        // @ts-expect-error: no logical table `tasks`
        tables: { tasks: "x" },
      },
    };

    const columns: BlocksConfig = {
      tasks: {
        columns: {
          // @ts-expect-error: no column `name` on `items`
          items: { name: "x" },
        },
      },
    };

    const functions: BlocksConfig = {
      tasks: {
        // @ts-expect-error: no function `list_work_items`
        functions: { list_work_items: "x" },
      },
    };

    const permissions: BlocksConfig = {
      tasks: {
        // @ts-expect-error: no action `archive`
        permissions: { archive: "x" },
      },
    };

    expectTypeOf([tables, columns, functions, permissions]).toBeArray();
  });
});
