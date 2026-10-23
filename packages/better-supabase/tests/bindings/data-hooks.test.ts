import { QueryClient } from "@tanstack/query-core";
import { describe, expect, it } from "vitest";

import type { DataEngine } from "../../src/bindings/data-engine.ts";
import type { Result } from "../../src/core/result.ts";

import { memoryEngine } from "../../src/bindings/data-engine.ts";
import {
  createDataList,
  createDataOne,
  dataTarget,
} from "../../src/bindings/data-hooks.ts";
import { DbException } from "../../src/core/db-exception.ts";
import { dbError } from "../../src/core/errors.ts";
import { err, ok } from "../../src/core/result.ts";
import { queryEngine } from "../../src/query/engine.ts";

interface Ticket {
  readonly id: string;
  readonly title: string;
}

/** A table in memory with the contract's verbs; `fail` makes writes fail. */
function tickets(rows: Ticket[]) {
  const state = { rows, fail: false, gate: Promise.resolve() };

  const answer = async <T>(value: () => T): Promise<Result<T>> => {
    await state.gate;

    return state.fail ? err(dbError("check", "no")) : ok(value());
  };

  const source = {
    list: (options?: { readonly title?: string }) =>
      answer(() =>
        state.rows.filter(
          (row) => options?.title === undefined || row.title === options.title,
        ),
      ),
    get: (id: string) =>
      answer(() => state.rows.find((row) => row.id === id) ?? null),
    create: (input: { readonly title: string }) =>
      answer(() => {
        const row = { id: `t${state.rows.length + 1}`, ...input };
        state.rows = [...state.rows, row];

        return row;
      }),
    update: (id: string, patch: Partial<Ticket>) =>
      answer(() => {
        state.rows = state.rows.map((row) =>
          row.id === id ? { ...row, ...patch } : row,
        );

        return state.rows.find((row) => row.id === id);
      }),
    delete: (id: string) =>
      answer(() => {
        state.rows = state.rows.filter((row) => row.id !== id);

        return id;
      }),
  };

  return { state, source };
}

const settle = () =>
  new Promise((resolve) => {
    setTimeout(resolve, 10);
  });

const engines: [string, () => DataEngine][] = [
  ["memory", memoryEngine],
  ["TanStack Query", () => queryEngine(new QueryClient())],
];

describe.each(engines)("the data hooks on the %s engine", (_, engine) => {
  const setup = (rows: Ticket[]) => {
    const table = tickets(rows);

    const client = { db: { tickets: table.source }, engine: engine() };

    const target = dataTarget(
      client,
      "tickets",
      (db: typeof client.db) => db.tickets,
    );

    return { ...table, target };
  };

  it("lists rows and shows pending until the first answer", async () => {
    const { target } = setup([{ id: "t1", title: "Printer" }]);
    const list = createDataList(target, undefined);

    expect(list.getSnapshot().isPending).toBe(true);
    const stop = list.subscribe(() => undefined);
    await settle();

    expect(list.getSnapshot()).toMatchObject({
      isPending: false,
      status: "success",
      data: [{ id: "t1", title: "Printer" }],
    });
    stop();
  });

  it("reads one row", async () => {
    const { target } = setup([{ id: "t1", title: "Printer" }]);
    const one = createDataOne(target, "t1");
    const stop = one.subscribe(() => undefined);
    await settle();

    expect(one.getSnapshot().data).toEqual({ id: "t1", title: "Printer" });
    stop();
  });

  it("adds a created row at once and keeps it after the refetch", async () => {
    const { state, target } = setup([]);
    const list = createDataList(target, undefined);
    const stop = list.subscribe(() => undefined);
    await settle();

    let release = (): void => undefined;
    state.gate = new Promise((resolve) => {
      release = resolve;
    });

    const created = list.actions.create({ title: "Printer" });

    expect(list.getSnapshot().data).toEqual([
      { id: undefined, title: "Printer" },
    ]);
    release();

    await expect(created).resolves.toEqual({ id: "t1", title: "Printer" });
    await settle();
    expect(list.getSnapshot().data).toEqual([{ id: "t1", title: "Printer" }]);
    stop();
  });

  it("updates and deletes rows in the cached lists", async () => {
    const { target } = setup([
      { id: "t1", title: "Printer" },
      { id: "t2", title: "Scanner" },
    ]);

    const list = createDataList(target, undefined);
    const stop = list.subscribe(() => undefined);
    await settle();

    await list.actions.update("t1", { title: "Printer down" });
    await list.actions.delete("t2");
    await settle();

    expect(list.getSnapshot().data).toEqual([
      { id: "t1", title: "Printer down" },
    ]);
    stop();
  });

  it("rolls back and rejects with a DbException when a write fails", async () => {
    const { state, target } = setup([{ id: "t1", title: "Printer" }]);
    const list = createDataList(target, undefined);
    const stop = list.subscribe(() => undefined);
    await settle();

    state.fail = true;
    const deleted = list.actions.delete("t1");

    await expect(deleted).rejects.toBeInstanceOf(DbException);
    expect(list.getSnapshot().data).toEqual([{ id: "t1", title: "Printer" }]);
    stop();
  });

  it("shows a failed read as an error", async () => {
    const { state, target } = setup([]);
    state.fail = true;
    const list = createDataList(target, undefined);
    const stop = list.subscribe(() => undefined);
    await settle();

    expect(list.getSnapshot()).toMatchObject({
      status: "error",
      isPending: false,
      error: { kind: "check" },
    });
    stop();
  });

  it("keeps one cache scope per organization", () => {
    const { source } = tickets([]);

    const scope = (organization: string) =>
      dataTarget(
        { db: { tickets: source }, tenant: organization },
        "tickets",
        (db: { tickets: typeof source }) => db.tickets,
      ).scope;

    expect(scope("org-1")).toEqual(["bsb", "tickets", "org-1"]);
    expect(scope("org-2")).not.toEqual(scope("org-1"));
  });
});
