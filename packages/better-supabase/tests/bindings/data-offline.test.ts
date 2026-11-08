import { describe, expect, it, vi } from "vitest";

import type { Result } from "../../src/core/result.ts";
import type { PowerSyncDatabaseLike } from "../../src/powersync/index.ts";

import { memoryEngine } from "../../src/bindings/data-engine.ts";
import {
  createDataList,
  createDataOne,
  dataTarget,
} from "../../src/bindings/data-hooks.ts";
import { dbError } from "../../src/core/errors.ts";
import { err, ok } from "../../src/core/result.ts";
import { powersyncEngine } from "../../src/powersync/index.ts";

interface Ticket {
  readonly id: string;
  readonly title: string;
}

/** A table whose calls the test counts, and whose reads can fail. */
function tickets(rows: Ticket[]) {
  const state = { rows, failReads: false, calls: [] as string[] };

  const source = {
    list: (): Promise<Result<readonly Ticket[]>> => {
      state.calls.push("list");

      return Promise.resolve(
        state.failReads
          ? err(dbError("network", "offline", { status: 0 }))
          : ok(state.rows),
      );
    },
    get: (id: string): Promise<Result<Ticket | null>> => {
      state.calls.push(`get:${id}`);

      return Promise.resolve(
        ok(state.rows.find((row) => row.id === id) ?? null),
      );
    },
    create: (input: { readonly title: string }): Promise<Result<Ticket>> => {
      state.calls.push(`create:${input.title}`);
      const row = { id: `t${state.rows.length + 1}`, ...input };
      state.rows = [...state.rows, row];

      return Promise.resolve(ok(row));
    },
    update: (id: string, _patch: Partial<Ticket>): Promise<Result<Ticket>> => {
      state.calls.push(`update:${id}`);

      return Promise.resolve(err(dbError("check", "no")));
    },
    delete: (id: string): Promise<Result<string>> => Promise.resolve(ok(id)),
  };

  return { state, source };
}

const settle = () =>
  new Promise((resolve) => {
    setTimeout(resolve, 10);
  });

const setup = (rows: Ticket[]) => {
  const table = tickets(rows);
  const client = { db: { tickets: table.source }, engine: memoryEngine() };

  return {
    ...table,
    target: dataTarget(client, "tickets", (db: typeof client.db) => db.tickets),
  };
};

describe("the offline data controllers", () => {
  it("leaves a plain read alone and reports no offline flag", async () => {
    const { target, state } = setup([{ id: "t1", title: "A" }]);
    const list = createDataList(target, undefined);
    const stop = list.subscribe(() => undefined);
    await settle();

    expect(state.calls).toEqual(["list"]);
    expect(list.getSnapshot()).toMatchObject({ status: "success" });
    expect(list.getSnapshot().offline).toBeUndefined();
    stop();
  });

  it("holds the first read while offline and runs it on reconnect", async () => {
    const { target, state } = setup([{ id: "t1", title: "A" }]);
    const list = createDataList(target, undefined, { offline: true });
    const stop = list.subscribe(() => undefined);
    await settle();

    expect(state.calls).toEqual([]);

    expect(list.getSnapshot()).toMatchObject({
      offline: true,
      status: "idle",
      error: undefined,
      isPending: true,
    });

    list.actions.setOffline(false);
    await settle();

    expect(state.calls).toEqual(["list"]);

    expect(list.getSnapshot()).toMatchObject({
      offline: false,
      status: "success",
      data: [{ id: "t1", title: "A" }],
    });

    stop();
  });

  it("keeps the last rows and shows no error when a read fails offline", async () => {
    const { target, state } = setup([{ id: "t1", title: "A" }]);
    const list = createDataList(target, undefined);
    const stop = list.subscribe(() => undefined);
    await settle();

    list.actions.setOffline(true);
    state.failReads = true;
    list.actions.refetch();
    await settle();

    expect(list.getSnapshot()).toMatchObject({
      offline: true,
      status: "success",
      error: undefined,
      data: [{ id: "t1", title: "A" }],
    });

    state.failReads = false;
    state.rows = [{ id: "t2", title: "B" }];
    list.actions.setOffline(false);
    await settle();

    expect(list.getSnapshot().data).toEqual([{ id: "t2", title: "B" }]);
    stop();
  });

  it("pauses a single row the same way", async () => {
    const { target, state } = setup([{ id: "t1", title: "A" }]);
    const one = createDataOne(target, "t1", { offline: true });
    const stop = one.subscribe(() => undefined);
    await settle();

    expect(state.calls).toEqual([]);

    one.actions.setOffline(false);
    await settle();

    expect(one.getSnapshot().data).toEqual({ id: "t1", title: "A" });
    stop();
  });

  it("queues a write with its optimistic row and sends it on reconnect", async () => {
    const { target, state } = setup([]);
    const list = createDataList(target, undefined);
    const stop = list.subscribe(() => undefined);
    await settle();

    list.actions.setOffline(true);
    const created = list.actions.create({ title: "Queued" });
    await settle();

    expect(state.calls).toEqual(["list"]);

    expect(list.getSnapshot().data).toEqual([
      { title: "Queued", id: undefined },
    ]);

    list.actions.setOffline(false);

    await expect(created).resolves.toEqual({ id: "t1", title: "Queued" });
    expect(state.calls).toContain("create:Queued");
    stop();
  });

  it("rolls a held write back when it fails after the reconnect", async () => {
    const { target } = setup([{ id: "t1", title: "A" }]);
    const list = createDataList(target, undefined);
    const stop = list.subscribe(() => undefined);
    await settle();

    list.actions.setOffline(true);
    const updated = list.actions.update("t1", { title: "B" });
    const failed = vi.fn();
    updated.catch(failed);
    await settle();

    expect(list.getSnapshot().data).toEqual([{ id: "t1", title: "B" }]);

    list.actions.setOffline(false);
    await settle();

    expect(failed).toHaveBeenCalledOnce();
    expect(list.getSnapshot().data).toEqual([{ id: "t1", title: "A" }]);
    stop();
  });

  it("ignores a repeated value", async () => {
    const { target, state } = setup([]);
    const list = createDataList(target, undefined, { offline: true });
    const stop = list.subscribe(() => undefined);

    list.actions.setOffline(true);
    list.actions.setOffline(false);
    list.actions.setOffline(false);
    await settle();

    expect(state.calls).toEqual(["list"]);
    stop();
  });

  it("never waits on an engine over a local database", async () => {
    const database: PowerSyncDatabaseLike = {
      getAll: () => Promise.resolve([]),
      execute: () => Promise.resolve(undefined),
      writeTransaction: (callback) => callback(database),
      onChange: () => () => undefined,
    };

    const table = tickets([{ id: "t1", title: "A" }]);

    const client = {
      db: { tickets: table.source },
      engine: powersyncEngine(database),
    };

    const target = dataTarget(
      client,
      "tickets",
      (db: typeof client.db) => db.tickets,
    );

    const list = createDataList(target, undefined, { offline: true });
    const stop = list.subscribe(() => undefined);
    await settle();

    expect(table.state.calls).toEqual(["list"]);
    expect(list.getSnapshot().offline).toBe(false);
    stop();
  });
});
