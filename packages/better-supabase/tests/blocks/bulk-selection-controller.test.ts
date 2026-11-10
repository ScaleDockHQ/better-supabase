import { describe, expect, it, vi } from "vitest";

import type { BulkOutcome } from "../../src/blocks/bulk-actions/index.ts";

import { createBulkSelectionController } from "../../src/blocks/bulk-actions/index.ts";

const now = (results: { id: string; ok: boolean }[]): BulkOutcome => ({
  mode: "now",
  total: results.length,
  succeeded: results.filter((r) => r.ok).length,
  failed: results.filter((r) => !r.ok).length,
  results: results.map((r) => ({ ...r, error: null })),
});

describe("createBulkSelectionController", () => {
  it("selects, toggles and clears rows without repeats", () => {
    const c = createBulkSelectionController({ run: vi.fn() });

    c.actions.select("a");
    c.actions.select("a");
    c.actions.selectMany(["b", "c"]);
    c.actions.toggle("b");
    c.actions.deselect("c");

    expect(c.getSnapshot().selected).toEqual(["a"]);

    c.actions.clear();
    expect(c.getSnapshot().selected).toEqual([]);
  });

  it("does nothing without a selection", async () => {
    const run = vi.fn();
    const c = createBulkSelectionController({ run });

    expect(await c.actions.run({ action: "trash.trash" })).toBeUndefined();
    expect(run).not.toHaveBeenCalled();
  });

  it("keeps only the failed rows selected after a run", async () => {
    const run = vi.fn(() =>
      Promise.resolve(
        now([
          { id: "a", ok: true },
          { id: "b", ok: false },
        ]),
      ),
    );

    const c = createBulkSelectionController({ run });
    c.actions.selectMany(["a", "b"]);

    const outcome = await c.actions.run({
      action: "tags.set",
      args: { add: ["x"] },
    });

    expect(run).toHaveBeenCalledWith({
      rows: ["a", "b"],
      action: "tags.set",
      args: { add: ["x"] },
    });
    expect(outcome?.mode).toBe("now");
    expect(c.getSnapshot()).toMatchObject({ selected: ["b"], pending: false });
  });

  it("reports a throw as error and keeps the selection", async () => {
    const boom = new Error("offline");

    const c = createBulkSelectionController({
      run: () => Promise.reject(boom),
    });

    c.actions.select("a");

    expect(await c.actions.run({ action: "trash.trash" })).toBeUndefined();
    expect(c.getSnapshot()).toMatchObject({
      error: boom,
      pending: false,
      selected: ["a"],
    });
  });

  it("follows a background run and stops watching on dispose", async () => {
    const stop = vi.fn();
    let push: ((p: never) => void) | undefined;

    const c = createBulkSelectionController({
      run: () =>
        Promise.resolve({ mode: "background", id: "r1", total: 2, topic: "t" }),
      watch: (_started, onProgress) => {
        push = onProgress as never;

        return stop;
      },
    });

    c.actions.select("a");
    const unsubscribe = c.subscribe(() => undefined);
    await c.actions.run({ action: "trash.trash" });

    push?.({ id: "r1", status: "running", position: 1, total: 2 } as never);
    expect(c.getSnapshot().progress).toMatchObject({ position: 1 });

    unsubscribe();
    expect(stop).toHaveBeenCalledOnce();
  });
});
