import { describe, expect, test } from "vitest";

import {
  addTable,
  appTableId,
  EMPTY_DESIGN,
  moveTables,
  undoHistory,
  HISTORY_LIMIT,
  initialHistory,
} from "../../src/create/index.ts";

const one = addTable(EMPTY_DESIGN, "projects");
const two = addTable(one, "tasks");

describe("undoHistory", () => {
  test("undoes and redoes steps", () => {
    let history = initialHistory(EMPTY_DESIGN);
    history = undoHistory(history, { type: "apply", value: one });
    history = undoHistory(history, { type: "apply", value: two });

    history = undoHistory(history, { type: "undo" });
    expect(history.present).toBe(one);

    history = undoHistory(history, { type: "redo" });
    expect(history.present).toBe(two);
  });

  test("a new step clears the redo stack", () => {
    let history = undoHistory(initialHistory(EMPTY_DESIGN), {
      type: "apply",
      value: one,
    });

    history = undoHistory(history, { type: "undo" });
    history = undoHistory(history, { type: "apply", value: two });

    expect(history.future).toEqual([]);
    expect(undoHistory(history, { type: "redo" })).toBe(history);
  });

  test("a drag is one step", () => {
    const id = appTableId("projects");

    let history = undoHistory(initialHistory(EMPTY_DESIGN), {
      type: "apply",
      value: one,
    });

    for (const x of [10, 20, 30]) {
      history = undoHistory(history, {
        type: "drag",
        value: moveTables(history.present, { [id]: [x, 0] }),
      });
    }

    history = undoHistory(history, { type: "commitDrag" });
    expect(history.past).toHaveLength(2);

    history = undoHistory(history, { type: "undo" });
    expect(history.present).toBe(one);
  });

  test("amend changes the current step without a new one", () => {
    let history = undoHistory(initialHistory(EMPTY_DESIGN), {
      type: "apply",
      value: one,
    });

    history = undoHistory(history, { type: "amend", value: two });
    expect(history.present).toBe(two);
    expect(history.past).toEqual([EMPTY_DESIGN]);

    history = undoHistory(history, { type: "undo" });
    expect(history.present).toBe(EMPTY_DESIGN);

    history = undoHistory(history, { type: "redo" });
    expect(history.present).toBe(two);
  });

  test("keeps at most HISTORY_LIMIT steps", () => {
    let history = initialHistory(EMPTY_DESIGN);

    for (let index = 0; index < HISTORY_LIMIT + 10; index += 1) {
      history = undoHistory(history, {
        type: "apply",
        value: addTable(EMPTY_DESIGN, `t${String(index)}`),
      });
    }

    expect(history.past).toHaveLength(HISTORY_LIMIT);
  });

  test("reset replaces the design and clears the history", () => {
    const history = undoHistory(
      undoHistory(initialHistory(EMPTY_DESIGN), { type: "apply", value: one }),
      { type: "reset", value: two },
    );

    expect(history).toEqual(initialHistory(two));
  });
});
