import { describe, expect, it, vi } from "vitest";

import { createBoardController } from "../../src/blocks/pipelines/index.ts";

const lanes = () => [
  { id: "new", cards: [{ id: "1" }, { id: "2" }] },
  { id: "won", cards: [{ id: "3" }] },
];

const ids = (c: ReturnType<typeof createBoardController>, lane: string) =>
  c
    .getSnapshot()
    .lanes.find((l) => l.id === lane)
    ?.cards.map((card) => card.id);

describe("createBoardController", () => {
  it("moves a card at once and saves it", async () => {
    const move = vi.fn(() => Promise.resolve());
    const c = createBoardController({ lanes: lanes(), move });

    const saved = c.actions.move({ cardId: "1", to: "won", index: 0 });

    expect(ids(c, "new")).toEqual(["2"]);
    expect(ids(c, "won")).toEqual(["1", "3"]);
    expect(c.getSnapshot().saving).toBe(1);
    expect(await saved).toBe(true);
    expect(c.getSnapshot().saving).toBe(0);
    expect(move).toHaveBeenCalledWith({
      cardId: "1",
      from: "new",
      to: "won",
      index: 0,
    });
  });

  it("appends without an index and reorders inside a lane", async () => {
    const c = createBoardController({
      lanes: lanes(),
      move: () => Promise.resolve(),
    });

    await c.actions.move({ cardId: "1", to: "won" });
    expect(ids(c, "won")).toEqual(["3", "1"]);

    await c.actions.move({ cardId: "3", to: "won", index: 1 });
    expect(ids(c, "won")).toEqual(["1", "3"]);
  });

  it("puts the card back when the save fails", async () => {
    const boom = new Error("conflict");

    const c = createBoardController({
      lanes: lanes(),
      move: () => Promise.reject(boom),
    });

    expect(await c.actions.move({ cardId: "1", to: "won" })).toBe(false);
    expect(ids(c, "new")).toEqual(["1", "2"]);
    expect(c.getSnapshot()).toMatchObject({ saving: 0, error: boom });
  });

  it("ignores no-op, unknown card and unknown lane moves", async () => {
    const move = vi.fn(() => Promise.resolve());
    const c = createBoardController({ lanes: lanes(), move });

    expect(await c.actions.move({ cardId: "1", to: "new", index: 0 })).toBe(
      false,
    );
    expect(await c.actions.move({ cardId: "9", to: "won" })).toBe(false);
    expect(await c.actions.move({ cardId: "1", to: "nowhere" })).toBe(false);
    expect(move).not.toHaveBeenCalled();
  });

  it("takes fresh lanes from the server", () => {
    const c = createBoardController({
      lanes: lanes(),
      move: () => Promise.resolve(),
    });

    c.actions.setLanes([{ id: "new", cards: [] }]);
    expect(c.getSnapshot().lanes).toHaveLength(1);
  });
});
