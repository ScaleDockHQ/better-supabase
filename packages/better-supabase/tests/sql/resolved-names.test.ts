import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../src/config/blocks.ts";
import type { ModuleNames } from "../../src/sql/context.ts";

import { SQL_MODULES } from "../../src/sql/index.ts";
import { resolveNames } from "../../src/sql/resolved-names.ts";

const namesOf = (module: string): ModuleNames => {
  const names = SQL_MODULES[module]?.names;

  if (names === undefined) {
    throw new Error(`no module ${module}`);
  }

  return names;
};

const resolve = (module: string, blocks: AnyBlocksConfig) =>
  resolveNames(module, namesOf(module), blocks);

describe("resolveNames", () => {
  it("keeps every default name without entities", () => {
    const resolved = resolve("work-items", {});

    expect(resolved.naming.renamed).toBe(false);
    expect(resolved.tenant.singular).toBe("organization");
    expect(resolved.entities["work_item"]?.to.plural).toBe("work_items");
  });

  it("renames the entities a block config names, and the tenant", () => {
    const resolved = resolve("work-items", {
      tenant: { entities: { organization: "workspace" } },
      "work-items": {
        entities: {
          work_item: { name: "task", url: "/tasks/{identifier}" },
          project: "initiative",
        },
      },
    });

    const rename = (name: string): string => resolved.naming.rename(name);

    expect(
      [
        "work_items",
        "work_item_id",
        "create_work_item",
        "work_items.read",
        "work_item.created",
        "work-items/",
        "workItemId",
        "saveProject",
        "WorkItem",
        "organization_id",
      ].map(rename),
    ).toEqual([
      "tasks",
      "task_id",
      "create_task",
      "tasks.read",
      "task.created",
      "tasks/",
      "taskId",
      "saveInitiative",
      "Task",
      "workspace_id",
    ]);
    expect(resolved.entities["work_item"]).toMatchObject({
      to: { singular: "task", plural: "tasks" },
      url: "/tasks/{identifier}",
      subject: { title: "title" },
    });
  });

  it("renames the primary entity from the string shorthand", () => {
    expect(
      resolve("deals", { deals: { entities: "opportunity" } }).naming.rename(
        "list_deals",
      ),
    ).toBe("list_opportunities");
  });

  it("drops the subject when the config sets subject: false", () => {
    const resolved = resolve("work-items", {
      "work-items": {
        entities: { work_item: { name: "task", subject: false } },
      },
    });

    expect(resolved.entities["work_item"]?.subject).toBeUndefined();
  });

  it("rejects unknown entities, bad names, placeholders and nested nouns", () => {
    expect(() =>
      resolve("work-items", { "work-items": { entities: { work: "task" } } }),
    ).toThrow('blocks.work-items.entities: unknown entity "work"');
    expect(() =>
      resolve("work-items", {
        "work-items": { entities: { work_item: "Task" } },
      }),
    ).toThrow("is not a lowercase identifier");
    expect(() =>
      resolve("work-items", {
        "work-items": {
          entities: { work_item: { name: "task", url: "/tasks/{slug}" } },
        },
      }),
    ).toThrow('"{slug}" is not a column of the entity\'s table');
    expect(() =>
      resolve("work-items", {
        "work-items": { entities: { work_item: "project_task" } },
      }),
    ).toThrow('"project_task" contains "project"');
    expect(() =>
      resolve("work-items", {
        "work-items": { entities: { project: "organization_project" } },
      }),
    ).toThrow('contains "organization"');
  });

  it("rejects the shorthand on a block without a primary entity", () => {
    expect(() =>
      resolve("parties", { parties: { entities: "client" } }),
    ).toThrow("the block has no primary entity");
  });
});
