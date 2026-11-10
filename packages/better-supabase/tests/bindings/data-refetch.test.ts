import { QueryClient } from "@tanstack/query-core";
import { describe, expect, it } from "vitest";

import type { DataEngine } from "../../src/bindings/data-engine.ts";
import type { Result } from "../../src/core/result.ts";

import { memoryEngine } from "../../src/bindings/data-engine.ts";
import { createDataList, dataTarget } from "../../src/bindings/data-hooks.ts";
import { DbException } from "../../src/core/db-exception.ts";
import { dbError } from "../../src/core/errors.ts";
import { err, ok } from "../../src/core/result.ts";
import { queryEngine } from "../../src/query/engine.ts";

/**
 * What a write does to the lists the hooks follow, pinned for ADR 0647: every
 * write settles with one `invalidate` of its scope, a realtime echo adds one
 * more, and a load that was superseded never overwrites newer data. These tests
 * hold for the memory and TanStack Query engines, so a later change to how
 * loads are shared has to keep them green.
 */

interface Ticket {
  readonly id: string;
  readonly title: string;
}

interface Load {
  readonly rows: Ticket[];
  readonly resolve: () => void;
  readonly reject: (error: unknown) => void;
}

/**
 * A table whose list reads wait until the test releases them, and answer with
 * the rows as they were when the read started, as a database snapshot does.
 */
function slowTickets(initial: Ticket[]) {
  const state = { rows: initial, loads: [] as Load[], fail: false };

  const source = {
    list: () =>
      new Promise<Result<Ticket[]>>((done) => {
        const rows = [...state.rows];

        state.loads.push({
          rows,
          resolve: () => {
            done(ok(rows));
          },
          reject: () => {
            done(err(dbError("unexpected", "load failed")));
          },
        });
      }),
    get: () => Promise.resolve(ok(null)),
    create: (input: { readonly title: string }) =>
      Promise.resolve(
        state.fail
          ? err(dbError("check", "no"))
          : (() => {
              const row = { id: `t${state.rows.length + 1}`, ...input };
              state.rows = [...state.rows, row];

              return ok(row);
            })(),
      ),
    update: () => Promise.resolve(ok(undefined)),
    delete: (id: string) =>
      Promise.resolve(
        state.fail
          ? err(dbError("check", "no"))
          : (() => {
              state.rows = state.rows.filter((row) => row.id !== id);

              return ok(id);
            })(),
      ),
  };

  return { state, source };
}

const tick = () =>
  new Promise((resolve) => {
    setTimeout(resolve, 5);
  });

function feed() {
  const listeners = new Set<(tables: readonly string[]) => void>();

  return {
    subscribe: (onChange: (tables: readonly string[]) => void) => {
      listeners.add(onChange);

      return () => {
        listeners.delete(onChange);
      };
    },
    emit: (table: string) => {
      for (const listener of listeners) {
        listener([table]);
      }
    },
  };
}

const engines: [string, (live: ReturnType<typeof feed>) => DataEngine][] = [
  ["memory", (live) => memoryEngine({ live })],
  ["TanStack Query", (live) => queryEngine(new QueryClient(), { live })],
];

describe.each(engines)(
  "refetching after writes on the %s engine",
  (_, make) => {
    const setup = (rows: Ticket[]) => {
      const table = slowTickets(rows);
      const live = feed();
      const client = { db: { tickets: table.source }, engine: make(live) };

      const target = dataTarget(
        client,
        "tickets",
        (db: typeof client.db) => db.tickets,
      );

      const list = createDataList(target, undefined);
      const stop = list.subscribe(() => undefined);

      /** Releases every read that is waiting, oldest first. */
      const release = async () => {
        for (const load of table.state.loads.splice(0)) {
          load.resolve();
          await tick();
        }
      };

      return { ...table, list, live, stop, release };
    };

    it("reads once for the first answer, once for a write and once for its echo", async () => {
      const { state, list, live, stop, release } = setup([]);
      await tick();
      expect(state.loads).toHaveLength(1);
      await release();

      const created = list.actions.create({ title: "Printer" });
      await created;
      await tick();
      expect(state.loads).toHaveLength(1);
      await release();

      live.emit("tickets");
      await tick();
      expect(state.loads).toHaveLength(1);
      await release();

      expect(list.getSnapshot().data).toEqual([{ id: "t1", title: "Printer" }]);
      stop();
    });

    it("keeps the newer rows when an older read answers last", async () => {
      const { state, list, live, stop, release } = setup([
        { id: "t1", title: "Printer" },
      ]);

      await tick();
      await release();

      await list.actions.delete("t1");
      await tick();
      live.emit("tickets");
      await tick();

      // The write's read and the echo's read both started after the delete, but
      // a read that started before it would see the old row: start one by hand
      // order, then answer the newest first and the oldest last.
      state.rows = [{ id: "t1", title: "Printer" }];
      list.actions.refetch();
      await tick();
      const stale = state.loads.pop()!;
      state.rows = [];
      list.actions.refetch();
      await tick();
      const fresh = state.loads.pop()!;

      fresh.resolve();
      await tick();
      stale.resolve();
      await tick();
      await release();

      expect(list.getSnapshot().data).toEqual([]);
      stop();
    });

    it("keeps the last rows and reports the error when a refetch fails, then recovers", async () => {
      const { state, list, live, stop, release } = setup([
        { id: "t1", title: "Printer" },
      ]);

      await tick();
      await release();

      live.emit("tickets");
      await tick();
      state.loads.pop()!.reject(new Error("offline"));
      await tick();

      expect(list.getSnapshot()).toMatchObject({
        status: "error",
        data: [{ id: "t1", title: "Printer" }],
        error: { kind: "unexpected" },
      });

      live.emit("tickets");
      await tick();
      await release();
      expect(list.getSnapshot()).toMatchObject({ status: "success" });
      stop();
    });

    it("rolls a failed write back and still reads once", async () => {
      const { state, list, stop, release } = setup([
        { id: "t1", title: "Printer" },
      ]);

      await tick();
      await release();

      state.fail = true;
      const deleted = list.actions.delete("t1");
      expect(list.getSnapshot().data).toEqual([]);

      await expect(deleted).rejects.toBeInstanceOf(DbException);
      expect(list.getSnapshot().data).toEqual([{ id: "t1", title: "Printer" }]);
      await tick();
      expect(state.loads).toHaveLength(1);
      await release();
      expect(list.getSnapshot().data).toEqual([{ id: "t1", title: "Printer" }]);
      stop();
    });

    it("drops an answer that arrives after the hook stopped following", async () => {
      const { state, list, live, stop } = setup([
        { id: "t1", title: "Printer" },
      ]);

      let notified = 0;
      stop();

      const unsubscribe = list.subscribe(() => {
        notified += 1;
      });

      await tick();
      const pending = state.loads.at(-1)!;
      unsubscribe();
      const before = notified;
      const started = state.loads.length;

      pending.resolve();
      live.emit("tickets");
      await tick();

      expect(notified).toBe(before);
      expect(state.loads).toHaveLength(started);
    });

    it("starts one read per concurrent write", async () => {
      const { state, list, stop, release } = setup([
        { id: "t1", title: "a" },
        { id: "t2", title: "b" },
        { id: "t3", title: "c" },
        { id: "t4", title: "d" },
        { id: "t5", title: "e" },
      ]);

      await tick();
      await release();

      await Promise.all(
        ["t1", "t2", "t3", "t4", "t5"].map((id) => list.actions.delete(id)),
      );
      await tick();

      // One scope invalidate per write; each starts its own read.
      expect(state.loads).toHaveLength(5);
      await release();
      expect(list.getSnapshot().data).toEqual([]);
      stop();
    });
  },
);
