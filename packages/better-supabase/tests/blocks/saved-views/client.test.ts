import { describe, expect, it, vi } from "vitest";

import type { SavedViewLike } from "../../../src/blocks/saved-views/client.ts";
import type { ListUrlState } from "../../../src/blocks/saved-views/query-state.ts";

import {
  createSavedViewsController,
  matchSavedViews,
} from "../../../src/blocks/saved-views/client.ts";
import { flush, mount } from "../../fixtures/ports.ts";

const view = (
  id: string,
  query: SavedViewLike["state"]["query"],
  extra: Partial<SavedViewLike> = {},
): SavedViewLike => ({
  id,
  name: id,
  scope: "user",
  isDefault: false,
  state: {
    ...(query === undefined ? {} : { query }),
    columns: { visible: ["name"] },
  },
  ...extra,
});

function setup(
  views: readonly SavedViewLike[],
  url: ListUrlState = {},
  options: { openDefault?: boolean } = {},
) {
  let urlState = url;
  const setUrlState = vi.fn((next: Record<string, unknown>) => {
    urlState = next;
  });
  const onApplyState = vi.fn();
  const calls = {
    load: vi.fn(async () => views),
    save: vi.fn(async () => undefined),
    remove: vi.fn(async () => undefined),
    duplicate: vi.fn(async () => undefined),
    setPreference: vi.fn(async () => undefined),
  };
  const controller = createSavedViewsController({
    ...calls,
    urlState: () => urlState,
    setUrlState,
    getState: () => ({ columns: { visible: ["name"] } }),
    onApplyState,
    ...options,
  });
  return { controller, calls, setUrlState, onApplyState, url: () => urlState };
}

describe("createSavedViewsController", () => {
  it("opens the default view for an empty URL and matches the URL against views", async () => {
    const open = view("open", undefined, { isDefault: true });
    const { controller, setUrlState, onApplyState } = setup([open], {
      q: null,
    });
    const mounted = mount(controller);
    await flush();
    expect(controller.getSnapshot().opened).toBe(open);
    expect(setUrlState).toHaveBeenCalledWith(
      expect.objectContaining({ q: null }),
    );
    expect(onApplyState).toHaveBeenCalledWith(
      { columns: { visible: ["name"] } },
      open,
    );
    const match = matchSavedViews(
      controller.getSnapshot(),
      {},
      {
        columns: { visible: ["name"] },
      },
    );
    expect(match).toMatchObject({ active: open, isDirty: false });
    expect(
      matchSavedViews(
        controller.getSnapshot(),
        {},
        {
          columns: { visible: ["email"] },
        },
      ),
    ).toMatchObject({ active: undefined, isDirty: true });
    expect(
      matchSavedViews(controller.getSnapshot(), {}, undefined).active,
    ).toBe(open);
    mounted.unmount();
  });

  it("saves, removes, duplicates and sets preferences, then loads again", async () => {
    const first = view("first", undefined);
    const { controller, calls } = setup([first], {}, { openDefault: false });
    const { view: current, unmount } = mount(controller);
    await flush();
    expect(current().opened).toBeUndefined();
    current().apply(first);
    await current().saveCurrent("Mine", "first");
    expect(calls.save).toHaveBeenCalledWith(
      expect.objectContaining({ name: "Mine", id: "first" }),
    );
    await current().remove("first");
    expect(current().opened).toBeUndefined();
    current().apply(first);
    await current().remove("other");
    expect(current().opened).toBe(first);
    await current().duplicate("first", "Copy", "tenant");
    expect(calls.duplicate).toHaveBeenCalledWith({
      id: "first",
      name: "Copy",
      scope: "tenant",
    });
    await current().duplicate("first", "Copy");
    await current().setPreference("first", { pinned: true });
    expect(calls.load).toHaveBeenCalledTimes(7);
    calls.load.mockRejectedValueOnce(new Error("offline"));
    await current().refresh();
    expect(current().error).toEqual(new Error("offline"));
    unmount();
  });

  it("asks for the missing callbacks and keeps a failed first load", async () => {
    const controller = createSavedViewsController({
      load: () => Promise.reject(new Error("offline")),
      urlState: () => ({}),
      setUrlState: () => undefined,
    });
    const { view: current, unmount } = mount(controller);
    await flush();
    expect(current().error).toEqual(new Error("offline"));
    await expect(current().saveCurrent("x")).rejects.toThrow(/`save`/);
    await expect(current().remove("x")).rejects.toThrow(/`remove`/);
    await expect(current().duplicate("x", "y")).rejects.toThrow(/`duplicate`/);
    await expect(current().setPreference("x", {})).rejects.toThrow(
      /`setPreference`/,
    );
    unmount();
    mount(controller).unmount();
  });

  it("drops a first load that finishes after it stopped", async () => {
    let finish = (_views: readonly SavedViewLike[]): void => undefined;
    const controller = createSavedViewsController({
      load: () =>
        new Promise<readonly SavedViewLike[]>((resolve) => {
          finish = resolve;
        }),
      urlState: () => ({}),
      setUrlState: () => undefined,
    });
    mount(controller).unmount();
    finish([view("late", undefined)]);
    await flush();
    expect(controller.getSnapshot().views).toBeUndefined();

    let fail = (_cause: Error): void => undefined;
    const failing = createSavedViewsController({
      load: () =>
        new Promise<readonly SavedViewLike[]>((_resolve, reject) => {
          fail = reject;
        }),
      urlState: () => ({}),
      setUrlState: () => undefined,
    });
    mount(failing).unmount();
    fail(new Error("late"));
    await flush();
    expect(failing.getSnapshot().error).toBeUndefined();
  });
});
