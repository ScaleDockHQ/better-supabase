import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../src/config/blocks.ts";
import type { BlockSqlNames } from "../../src/sql/context.ts";

import { SQL_MODULES } from "../../src/sql/index.ts";
import { entityType, resolveNames } from "../../src/sql/resolved-names.ts";

const namesOf = (module: string): BlockSqlNames => {
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
    const resolved = resolve("tasks", {});

    expect(resolved.naming.renamed).toBe(false);
    expect(resolved.functionNouns.renamed).toBe(false);
    expect(resolved.tenant.singular).toBe("organization");
    expect(resolved.entities["task"]?.to.plural).toBe("tasks");
    expect(resolved.formerName("create_task")).toBe("create_work_item");
    expect(entityType(resolved, "task")).toBe("task");
  });

  it("renames the entities a block config names, and the tenant", () => {
    const resolved = resolve("tasks", {
      memberships: { entities: { organization: "workspace" } },
      tasks: {
        entities: {
          task: { name: "ticket", url: "/tickets/{identifier}" },
          project: "initiative",
        },
      },
    });

    const rename = (name: string): string => resolved.naming.rename(name);

    expect(
      [
        "work_items",
        "work_item_id",
        "tasks.read",
        "work_item.created",
        "tasks/",
        "workItemId",
        "saveProject",
        "WorkItem",
        "organization_id",
      ].map(rename),
    ).toEqual([
      "tickets",
      "ticket_id",
      "tasks.read",
      "ticket.created",
      "tasks/",
      "ticketId",
      "saveInitiative",
      "Ticket",
      "workspace_id",
    ]);
    expect(rename(resolved.functionNouns.rename("create_task"))).toBe(
      "create_ticket",
    );
    expect(resolved.entities["task"]).toMatchObject({
      from: { singular: "work_item" },
      to: { singular: "ticket", plural: "tickets" },
      formerly: { from: { singular: "work_item" }, to: { singular: "task" } },
      url: "/tickets/{identifier}",
      subject: { title: "title" },
    });
    expect(entityType(resolved, "task")).toBe("ticket");
  });

  it("reads an entity key from before 0.46 as the new key", () => {
    const resolved = resolve("tasks", {
      tasks: { entities: { work_item: "ticket" } },
    });

    expect(resolved.entities["task"]?.to.singular).toBe("ticket");
    expect(resolved.naming.rename("work_items")).toBe("tickets");
  });

  it("renames the primary entity from the string shorthand", () => {
    expect(
      resolve("deals", { deals: { entities: "opportunity" } }).naming.rename(
        "list_deals",
      ),
    ).toBe("list_opportunities");
  });

  it("drops the subject when the config sets subject: false", () => {
    const resolved = resolve("tasks", {
      tasks: { entities: { task: { name: "ticket", subject: false } } },
    });

    expect(resolved.entities["task"]?.subject).toBeUndefined();
  });

  it("rejects unknown entities, bad names, placeholders and nested nouns", () => {
    expect(() =>
      resolve("tasks", { tasks: { entities: { work: "ticket" } } }),
    ).toThrow('blocks.tasks.names: unknown entity "work"');
    expect(() =>
      resolve("tasks", { tasks: { entities: { task: "Ticket" } } }),
    ).toThrow("is not a lowercase identifier");
    expect(() =>
      resolve("tasks", {
        tasks: {
          entities: { task: { name: "ticket", url: "/tickets/{slug}" } },
        },
      }),
    ).toThrow('"{slug}" is not a column of the entity\'s table');
    expect(() =>
      resolve("tasks", { tasks: { entities: { task: "project_task" } } }),
    ).toThrow('"project_task" contains "project"');
    expect(() =>
      resolve("tasks", {
        tasks: { entities: { project: "organization_project" } },
      }),
    ).toThrow('contains "organization"');
  });

  it("rejects the shorthand on a block without a primary entity", () => {
    expect(() =>
      resolve("contacts", { contacts: { entities: "client" } }),
    ).toThrow("the block has no primary entity");
  });
});
