import { namedPreset } from "better-supabase/preset";
import { describe, expect, test } from "vitest";

import { toggleBlock } from "../../lib/create";
import {
  createReducer,
  type CreateState,
  initialCreateState,
  presetOfState,
} from "../../lib/create-state";
import {
  addTable,
  appTableId,
  EMPTY_DESIGN,
  moveTables,
  placeTables,
} from "../../lib/design";

const minimal = namedPreset("minimal");
const start = initialCreateState(minimal, EMPTY_DESIGN);
const projects = addTable(EMPTY_DESIGN, "projects");

function run(
  state: CreateState,
  ...actions: Parameters<typeof createReducer>[1][]
) {
  return actions.reduce(createReducer, state);
}

describe("the /create state", () => {
  test("switching a block is one step Undo reverts", () => {
    const on = run(start, {
      type: "preset",
      update: (current) => toggleBlock(current, "comments"),
    });

    expect(presetOfState(on).blocks).toEqual(["profiles", "comments"]);
    expect(on.history.past).toHaveLength(1);

    expect(presetOfState(run(on, { type: "undo" })).blocks).toEqual([
      "profiles",
    ]);
  });

  test("other preset fields change without a step", () => {
    const camel = run(start, {
      type: "preset",
      update: (current) => ({ ...current, casing: "camel" }),
    });

    expect(presetOfState(camel).casing).toBe("camel");
    expect(camel.history.past).toEqual([]);
  });

  test("a dropped block and its placement are one step", () => {
    const point = { x: 40, y: 60 };

    const dropped = run(
      start,
      {
        type: "preset",
        update: (current) => toggleBlock(current, "comments"),
      },
      {
        type: "place",
        design: placeTables(
          EMPTY_DESIGN,
          { "better_supabase.comments": { x: 0, y: 0 } },
          point,
        ),
      },
    );

    expect(dropped.history.present.design.positions).toEqual({
      "better_supabase.comments": [40, 60],
    });
    expect(dropped.history.past).toHaveLength(1);

    const undone = run(dropped, { type: "undo" });
    expect(presetOfState(undone).blocks).toEqual(["profiles"]);
    expect(undone.history.present.design).toBe(EMPTY_DESIGN);
  });

  test("a drag is one step and keeps the blocks", () => {
    const id = appTableId("projects");
    let state = run(start, { type: "design", design: projects });

    for (const x of [10, 20, 30]) {
      state = run(state, {
        type: "drag",
        design: moveTables(state.history.present.design, { [id]: [x, 0] }),
      });
    }

    state = run(state, { type: "commitDrag" });
    expect(state.history.past).toHaveLength(2);
    expect(state.history.present.blocks).toBe(minimal.blocks);
    expect(run(state, { type: "undo" }).history.present.design).toBe(projects);
  });

  test("loading a link keeps the preset and clears the history", () => {
    const state = run(
      start,
      { type: "preset", update: (current) => toggleBlock(current, "tags") },
      { type: "load", design: projects },
    );

    expect(state.history.past).toEqual([]);
    expect(state.history.present.design).toBe(projects);
    expect(presetOfState(state).blocks).toEqual(["profiles", "tags"]);
  });

  test("restoring a draft replaces both", () => {
    const saas = namedPreset("saas");

    const state = run(start, {
      type: "restore",
      preset: saas,
      design: projects,
    });

    expect(presetOfState(state)).toBe(saas);
    expect(state.history.present.design).toBe(projects);
  });
});
