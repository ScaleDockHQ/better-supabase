import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import type {
  SearchHit,
  SearchUserItem,
} from "../../../src/blocks/search/search.ts";

import { createCommandSearchController } from "../../../src/blocks/search/client.ts";
import { failed, fakeKeyboard, mount, resolved } from "../../fixtures/ports.ts";

const hit = (subjectType: string, subjectId: string): SearchHit =>
  // SAFETY: the controller and groupHits read these fields.
  ({
    subjectType,
    subjectId,
    title: subjectId,
    url: null,
  }) as unknown as SearchHit;
const user = (subjectId: string): SearchUserItem =>
  // SAFETY: as above.
  ({
    subjectType: "note",
    subjectId,
    title: subjectId,
    url: null,
  }) as unknown as SearchUserItem;

function fakeClient() {
  return {
    search: vi.fn((q: string) => resolved([hit("note", q), hit("deal", "d1")])),
    recents: vi.fn(() => resolved([user("r1")])),
    favorites: vi.fn(() => resolved([user("f1")])),
    touch: vi.fn(() => resolved(true)),
    star: vi.fn(() => resolved(true)),
  };
}

beforeEach(() => {
  vi.useFakeTimers();
});
afterEach(() => {
  vi.useRealTimers();
});

describe("createCommandSearchController", () => {
  it("opens on mod+K, lists favorites and recents, and searches after the debounce", async () => {
    const client = fakeClient();
    const keyboard = fakeKeyboard();
    const { view, unmount } = mount(
      createCommandSearchController({
        // SAFETY: the fake has the methods the controller calls.
        client: client,
        keyboard: keyboard.port,
        organizationId: "org",
        types: ["note"],
        limit: 5,
        listLimit: 3,
      }),
    );
    keyboard.press({ key: "k", mod: true });
    expect(view().open).toBe(true);
    await vi.advanceTimersByTimeAsync(0);
    expect(client.recents).toHaveBeenCalledWith({ limit: 3, types: ["note"] });
    expect(view().groups.map((group) => group.key)).toEqual([
      "favorites",
      "recents",
    ]);

    view().setQuery(" rev ");
    view().setQuery(" rev  ");
    expect(view().loading).toBe(true);
    await vi.advanceTimersByTimeAsync(150);
    expect(client.search).toHaveBeenCalledTimes(1);
    expect(client.search).toHaveBeenCalledWith("rev", {
      limit: 5,
      organizationId: "org",
      types: ["note"],
    });
    expect(view().groups.map((group) => group.key)).toEqual(["note", "deal"]);
    expect(view().loading).toBe(false);

    await view().select(view().results[0]!);
    expect(view()).toMatchObject({ open: false, query: "" });
    expect(client.touch).toHaveBeenCalledWith("note", "rev");
    keyboard.press({ key: "k", mod: true });
    keyboard.press({ key: "k", mod: true });
    expect(view().open).toBe(false);
    unmount();
    expect(keyboard.bound()).toBe(0);
  });

  it("drops overtaken answers, keeps hits on a failed query and reports list errors", async () => {
    const client = fakeClient();
    const { view, unmount } = mount(
      createCommandSearchController({ client: client, debounceMs: 0 }),
    );
    view().setOpen(true);
    view().setOpen(true);
    view().setQuery("first");
    await vi.advanceTimersByTimeAsync(0);
    view().setQuery("second");
    await vi.advanceTimersByTimeAsync(0);
    expect(view().results.map((each) => each.subjectId)).toEqual([
      "second",
      "d1",
    ]);

    client.search.mockReturnValue(failed("boom"));
    view().setQuery("third");
    await vi.advanceTimersByTimeAsync(0);
    expect(view().error?.message).toBe("boom");
    expect(view().results).toHaveLength(2);
    expect(view().loading).toBe(false);

    client.recents.mockReturnValue(failed("no recents"));
    view().setQuery("");
    view().setOpen(false);
    view().setOpen(true);
    await vi.advanceTimersByTimeAsync(0);
    expect(view().error?.message).toBe("no recents");
    client.recents.mockReturnValue(resolved([]));
    client.favorites.mockReturnValue(failed("no favorites"));
    await view().star(user("f1"), false);
    expect(client.star).toHaveBeenCalledWith("note", "f1", false);
    expect(view().error?.message).toBe("no favorites");

    client.star.mockReturnValue(failed("denied"));
    await view().star(user("f1"));
    expect(view().error?.message).toBe("denied");
    client.touch.mockReturnValue(failed("gone"));
    await view().select(user("f1"));
    expect(view().error?.message).toBe("gone");
    expect(view().results).toEqual([]);
    unmount();
  });

  it("drops lists that load after the dialog closed", async () => {
    const client = fakeClient();
    const { view, unmount } = mount(
      createCommandSearchController({ client: client }),
    );
    view().setOpen(true);
    view().setOpen(false);
    await vi.advanceTimersByTimeAsync(0);
    expect(view().recents).toEqual([]);
    unmount();
  });
});
