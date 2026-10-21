import { describe, expect, it, vi } from "vitest";

import {
  createNotificationsController,
  unreadCount,
} from "../../../src/blocks/notifications/client.ts";
import {
  fakeAuth,
  fakeTopic,
  flush,
  mount,
  OTHER,
  SIGNED_OUT,
  signedIn,
} from "../../fixtures/ports.ts";

interface Item {
  readonly id: string;
  readonly readAt: string | null;
}

const item = (id: string, readAt: string | null = null): Item => ({
  id,
  readAt,
});

describe("createNotificationsController", () => {
  it("loads, merges sources and reloads on broadcasts and rejoins", async () => {
    const auth = fakeAuth();
    const topic = fakeTopic();
    let rows = [item("b"), item("a", "2026-01-01")];
    const onMessage = vi.fn();

    const controller = createNotificationsController<Item>({
      auth,
      ports: { topic: topic.port },
      topic: "notifications:u1",
      load: async () => rows,
      sources: [async () => [item("c")]],
      sort: (x, y) => x.id.localeCompare(y.id),
      onMessage,
    });

    expect(controller.getSnapshot().items).toBeUndefined();
    const { view, unmount } = mount(controller);
    await flush();
    expect(view().items?.map((each) => each.id)).toEqual(["a", "b", "c"]);
    expect(view().count).toBe(2);
    expect(view().status).toBe("subscribed");

    rows = [item("d")];
    topic.emit("notifications:u1", "notification_created", { id: "d" });
    await flush();
    expect(onMessage).toHaveBeenCalledWith("notification_created", { id: "d" });
    expect(view().items?.map((each) => each.id)).toEqual(["c", "d"]);
    rows = [];
    topic.rejoin("notifications:u1");
    await flush();
    expect(view().items).toHaveLength(1);

    unmount();
    expect(topic.open()).toEqual([]);
    expect(view().status).toBe("closed");
  });

  it("waits for a user, joins no topic for null and keeps load errors", async () => {
    const auth = fakeAuth(SIGNED_OUT);
    const topic = fakeTopic();

    const load = vi.fn(async (): Promise<readonly Item[]> => {
      throw new Error("offline");
    });

    const { view, unmount } = mount(
      createNotificationsController<Item>({
        auth,
        ports: { topic: topic.port },
        topic: null,
        load,
        count: (items) => items.length * 10,
      }),
    );

    await flush();
    expect(load).not.toHaveBeenCalled();
    auth.set(signedIn(OTHER));
    await flush();
    expect(view().error).toEqual(new Error("offline"));
    expect(topic.joined).toEqual([]);
    load.mockResolvedValue([item("x")]);
    await view().refresh();
    expect(view()).toMatchObject({ count: 10, error: undefined });
    unmount();
  });

  it("counts the items without a readAt", () => {
    expect(unreadCount([item("a"), item("b", "now"), "junk", null])).toBe(1);
  });
});
