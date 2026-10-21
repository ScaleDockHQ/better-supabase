import { describe, expect, it } from "vitest";

import type { BlockTransport } from "../../src/core/block-transport.ts";

import { defineBlock } from "../../src/blocks/define-block.ts";
import { renameBlock } from "../../src/blocks/rename-block.ts";
import { workItemsBlock } from "../../src/blocks/work-items/manifest.ts";
import { wrapTransport } from "../../src/core/block-hooks.ts";
import { blockNames } from "../../src/core/block-names.ts";

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

const TASK = {
  id: "w1",
  tenant_id: "o",
  number: 1,
  identifier: "T-1",
  title: "Ship",
  initiative_id: "p1",
  priority: 0,
  progress: 0,
  pipeline_id: "pl1",
  stage_id: "s1",
  stage_entered_at: "2026-10-20T09:00:00Z",
  state: "started",
  locked: false,
  rank: "V",
  archived_at: null,
  created_by: "u1",
  created_at: "2026-10-14T09:00:00Z",
  updated_at: "2026-10-14T09:00:00Z",
  assignees: [],
};

/** A SQL side that already speaks the renamed nouns. */
function sql(): {
  readonly calls: [string, Readonly<Record<string, unknown>>][];
  readonly transport: BlockTransport;
} {
  const calls: [string, Readonly<Record<string, unknown>>][] = [];

  const results: Readonly<Record<string, unknown>> = {
    list_tasks: [TASK],
    save_initiative: {
      id: "p1",
      key: "PAY",
      name: "Payments",
      status: "active",
    },
    update_tasks: {
      accepted: [{ taskId: "w1", field: "initiativeId" }],
      rejected: [],
    },
  };

  const transport: BlockTransport = {
    call: async (_schema, fn, args) => {
      calls.push([fn, args]);

      return results[fn];
    },
  };

  return { calls, transport: wrapTransport(transport, blockNames(NAMES)) };
}

describe("renameBlock", () => {
  it("renames the client's methods, arguments and results", async () => {
    const { calls, transport } = sql();
    const tasks = renameBlock(workItemsBlock, NAMES).create?.({ transport });

    const listed = await tasks?.list("o", { initiativeId: "p1" }).orThrow();

    const saved = await tasks
      ?.saveInitiative("o", { key: "PAY", name: "Payments" })
      .orThrow();

    const changed = await tasks
      ?.update([{ taskId: "w1", field: "initiativeId", value: "p2" }])
      .orThrow();

    expect({
      initiative: listed?.[0]?.initiativeId,
      saved: saved?.name,
      changed,
      calls: calls.map(([fn]) => fn),
      filter: calls[0]?.[1]["filter"],
      changes: calls[2]?.[1]["changes"],
    }).toEqual({
      initiative: "p1",
      saved: "Payments",
      changed: {
        accepted: [{ taskId: "w1", field: "initiativeId" }],
        rejected: [],
      },
      calls: ["list_tasks", "save_initiative", "update_tasks"],
      filter: { initiativeId: "p1" },
      changes: [{ taskId: "w1", field: "initiativeId", value: "p2" }],
    });
  });

  it("renames the event types and keeps the name", () => {
    const tasks = renameBlock(workItemsBlock, NAMES);

    expect({ name: tasks.name, types: tasks.events.types }).toEqual({
      name: "work-items",
      types: [
        "task.created",
        "task.updated",
        "task.assigned",
        "task.closed",
        "task.reopened",
        "task.archived",
        "task.deleted",
      ],
    });
  });

  it("runs hooks on the renamed client", async () => {
    const { transport } = sql();
    const seen: string[] = [];

    const tasks = renameBlock(workItemsBlock, NAMES).create?.({
      transport,
      hooks: {
        saveInitiative: {
          before: ([, initiative], info) => {
            seen.push(`${info.method}:${initiative.name}`);
          },
        },
      },
    });

    await tasks?.saveInitiative("o", { key: "PAY", name: "Payments" });

    expect(seen).toEqual(["saveInitiative:Payments"]);
  });

  it("gives the ports the client under the default names", () => {
    const block = defineBlock({
      name: "items",
      category: "work",
      create: () => ({ listWorkItems: () => "listed" }),
      provides: {
        sink: (client: { readonly listWorkItems: () => string }) => {
          client.listWorkItems();

          return;
        },
      },
    });

    const tasks = renameBlock(block, NAMES);
    const client = tasks.create?.({ transport: sql().transport });
    const provide = tasks.provides.sink;

    expect({
      method: client?.listTasks(),
      port: provide(client as never, {} as never),
    }).toEqual({ method: "listed", port: undefined });
  });

  it("returns the block itself when nothing is renamed", () => {
    expect(renameBlock(workItemsBlock, undefined)).toBe(workItemsBlock);
  });
});
