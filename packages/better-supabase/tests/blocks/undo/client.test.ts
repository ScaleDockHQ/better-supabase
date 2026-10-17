import { describe, expect, it, vi } from "vitest";

import type { UndoToken } from "../../../src/blocks/undo/undo.ts";

import { createUndoController } from "../../../src/blocks/undo/client.ts";
import { mount } from "../../fixtures/ports.ts";

// SAFETY: the controller passes tokens through untouched.
const token = (id: string) => ({ id }) as unknown as UndoToken;

describe("createUndoController", () => {
  it("pushes, caps and undoes the newest token", async () => {
    const apply = vi.fn(async () => undefined);
    const { view } = mount(createUndoController({ apply, limit: 2 }));
    view().push(null);
    view().push(token("a"), "A");
    view().push(token("b"));
    view().push(token("c"), "C");
    expect(view().entries.map((entry) => entry.label)).toEqual(["", "C"]);
    expect(view().canUndo).toBe(true);
    const undoing = view().undo();
    expect(view()).toMatchObject({ pending: true, canUndo: false });
    expect(await view().undo()).toBe(false);
    expect(await undoing).toBe(true);
    expect(apply).toHaveBeenCalledWith(token("c"));
    expect(view().entries).toHaveLength(1);
    view().clear();
    expect(await view().undo()).toBe(false);
  });

  it("drops a failed entry and keeps the error until the next push", async () => {
    const { view } = mount(
      createUndoController({
        apply: () => Promise.reject(new Error("changed since")),
      }),
    );

    view().push(token("a"));
    expect(await view().undo()).toBe(false);
    expect(view()).toMatchObject({
      entries: [],
      error: new Error("changed since"),
    });
    view().push(token("b"));
    expect(view().error).toBeUndefined();
  });
});
