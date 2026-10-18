import { describe, expect, test } from "vitest";

import {
  addTable,
  appTableId,
  EMPTY_DESIGN,
  moveTables,
} from "../../lib/design";
import {
  designHistory,
  HISTORY_LIMIT,
  initialHistory,
} from "../../lib/design-history";

const one = addTable(EMPTY_DESIGN, "projects");
const two = addTable(one, "tasks");

describe("designHistory", () => {
  test("undoes and redoes steps", () => {
    let history = initialHistory();
    history = designHistory(history, { type: "apply", design: one });
    history = designHistory(history, { type: "apply", design: two });

    history = designHistory(history, { type: "undo" });
    expect(history.present).toBe(one);

    history = designHistory(history, { type: "redo" });
    expect(history.present).toBe(two);
  });

  test("a new step clears the redo stack", () => {
    let history = designHistory(initialHistory(), {
      type: "apply",
      design: one,
    });

    history = designHistory(history, { type: "undo" });
    history = designHistory(history, { type: "apply", design: two });

    expect(history.future).toEqual([]);
    expect(designHistory(history, { type: "redo" })).toBe(history);
  });

  test("a drag is one step", () => {
    const id = appTableId("projects");

    let history = designHistory(initialHistory(), {
      type: "apply",
      design: one,
    });

    for (const x of [10, 20, 30]) {
      history = designHistory(history, {
        type: "drag",
        design: moveTables(history.present, { [id]: [x, 0] }),
      });
    }

    history = designHistory(history, { type: "commitDrag" });
    expect(history.past).toHaveLength(2);

    history = designHistory(history, { type: "undo" });
    expect(history.present).toBe(one);
  });

  test("keeps at most HISTORY_LIMIT steps", () => {
    let history = initialHistory();

    for (let index = 0; index < HISTORY_LIMIT + 10; index += 1) {
      history = designHistory(history, {
        type: "apply",
        design: addTable(EMPTY_DESIGN, `t${String(index)}`),
      });
    }

    expect(history.past).toHaveLength(HISTORY_LIMIT);
  });

  test("reset replaces the design and clears the history", () => {
    const history = designHistory(
      designHistory(initialHistory(), { type: "apply", design: one }),
      { type: "reset", design: two },
    );

    expect(history).toEqual(initialHistory(two));
  });
});
