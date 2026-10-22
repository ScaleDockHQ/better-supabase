import { QueryClient, skipToken } from "@tanstack/query-core";
import { describe, expect, it } from "vitest";

import { emitBlockEvent } from "../../src/core/block-events.ts";
import { dbError } from "../../src/core/errors.ts";
import { EventHub } from "../../src/core/events.ts";
import { AsyncResult, err, ok } from "../../src/core/result.ts";
import {
  blockQueries,
  invalidateOnBlockEvents,
} from "../../src/query/blocks.ts";
import { invalidateTables } from "../../src/query/invalidate.ts";

interface Task {
  readonly id: string;
  readonly title: string;
}

function tasksClient() {
  const rows: Task[] = [{ id: "t1", title: "Write docs" }];

  return {
    rows,
    calls: 0,
    listTasks(filter?: { readonly title?: string }) {
      this.calls += 1;

      return new AsyncResult(
        Promise.resolve(
          ok(
            rows.filter((row) => !filter?.title || row.title === filter.title),
          ),
        ),
      );
    },
    getTask(id: string) {
      const row = rows.find((each) => each.id === id);

      return new AsyncResult(
        Promise.resolve(row ? ok(row) : err(dbError("not_found", "no task"))),
      );
    },
    createTask(input: { readonly title: string }) {
      const row = { id: `t${rows.length + 1}`, title: input.title };
      rows.push(row);

      return new AsyncResult(Promise.resolve(ok(row)));
    },
    moveTask(id: string, position: number) {
      return new AsyncResult(Promise.resolve(ok({ id, position })));
    },
    issueTask(id: string) {
      return new AsyncResult(Promise.resolve(ok({ id })));
    },
  };
}

describe("blockQueries", () => {
  it("makes query options for read methods, keyed by block and method", async () => {
    const tasks = tasksClient();
    const queries = blockQueries({ tasks });
    const queryClient = new QueryClient();

    const options = queries.tasks.listTasks({ title: "Write docs" });
    expect(options.queryKey).toEqual([
      "bsb",
      "tasks",
      "listTasks",
      { title: "Write docs" },
    ]);
    expect(options.meta).toEqual({ bsTables: ["tasks"] });
    await expect(queryClient.query(options)).resolves.toEqual([
      { id: "t1", title: "Write docs" },
    ]);
    expect(queries.tasks.$key).toEqual(["bsb", "tasks"]);
  });

  it("throws a DbException for an error result", async () => {
    const queries = blockQueries({ tasks: tasksClient() });

    await expect(
      new QueryClient().query({ ...queries.tasks.getTask("t9"), retry: false }),
    ).rejects.toMatchObject({ error: { kind: "not_found" } });
  });

  it("passes skipToken through", () => {
    const queries = blockQueries({ tasks: tasksClient() });

    expect(queries.tasks.getTask(skipToken).queryFn).toBe(skipToken);
  });

  it("makes mutation options for other methods that invalidate the block", async () => {
    const tasks = tasksClient();
    const queries = blockQueries({ tasks });
    const queryClient = new QueryClient();

    await queryClient.query(queries.tasks.listTasks());

    const create = queries.tasks.createTask();
    const row = await create.mutationFn({ title: "Ship" });
    await create.onSuccess(row, { title: "Ship" }, undefined, {
      client: queryClient,
    });

    expect(
      queryClient.getQueryState(queries.tasks.listTasks().queryKey)
        ?.isInvalidated,
    ).toBe(true);
    await expect(
      queries.tasks.moveTask().mutationFn(["t1", 2]),
    ).resolves.toEqual({ id: "t1", position: 2 });
    expect(queries.tasks.issueTask().mutationKey).toEqual([
      "bsb",
      "tasks",
      "issueTask",
    ]);
  });
});

describe("invalidateOnBlockEvents", () => {
  it("makes the listed read methods stale, or all of them", async () => {
    const tasks = tasksClient();
    const queries = blockQueries({ tasks });
    const queryClient = new QueryClient();
    const events = new EventHub();

    const stop = invalidateOnBlockEvents(
      queryClient,
      { events },
      {
        tasks: {
          events: { types: ["task.created", "task.archived"] },
          invalidates: { "task.created": ["listTasks"] },
        },
      },
    );

    await queryClient.query(queries.tasks.listTasks());
    await queryClient.query(queries.tasks.getTask("t1"));

    const stale = (key: readonly unknown[]) =>
      queryClient.getQueryState(key)?.isInvalidated;

    emitBlockEvent<{ "task.created": { readonly id: string } }>(
      events,
      "task.created",
      { id: "t2" },
    );
    expect(stale(queries.tasks.listTasks().queryKey)).toBe(true);
    expect(stale(queries.tasks.getTask("t1").queryKey)).toBe(false);

    emitBlockEvent<{ "task.archived": { readonly id: string } }>(
      events,
      "task.archived",
      { id: "t1" },
    );
    expect(stale(queries.tasks.getTask("t1").queryKey)).toBe(true);
    stop();
  });
});

describe("one key space", () => {
  it("lets invalidateTables reach a block instance's queries", async () => {
    const queries = blockQueries({ tasks: tasksClient() });
    const queryClient = new QueryClient();

    await queryClient.query(queries.tasks.listTasks());
    await invalidateTables(queryClient, ["tasks"]);

    expect(
      queryClient.getQueryState(queries.tasks.listTasks().queryKey)
        ?.isInvalidated,
    ).toBe(true);
  });
});
