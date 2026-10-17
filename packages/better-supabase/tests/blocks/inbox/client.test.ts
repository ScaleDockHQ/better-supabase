import { afterEach, describe, expect, it, vi } from "vitest";

import {
  createConversationController,
  createInboxController,
  createInboxWidgetController,
} from "../../../src/blocks/inbox/client.ts";
import { memoryStorage } from "../../../src/client/ports.ts";
import {
  fakeAuth,
  fakeTopic,
  flush,
  mount,
  OTHER,
  SIGNED_OUT,
  USER,
} from "../../fixtures/ports.ts";

afterEach(() => {
  vi.useRealTimers();
});

describe("createInboxController", () => {
  it("loads the organization's conversations and reloads on pings", async () => {
    const topic = fakeTopic();
    let rows = ["a"];
    const onMessage = vi.fn();

    const { view, unmount } = mount(
      createInboxController({
        auth: fakeAuth(),
        ports: { topic: topic.port },
        organizationId: "org-1",
        topic: "support",
        load: async () => rows,
        onMessage,
      }),
    );

    await flush();
    expect(view().items).toEqual(["a"]);
    expect(topic.open()).toEqual(["support:org:org-1"]);
    rows = ["a", "b"];
    topic.emit("support:org:org-1", "message", { id: "m1" });
    await flush();
    expect(onMessage).toHaveBeenCalledWith("message", { id: "m1" });
    expect(view().items).toEqual(["a", "b"]);
    topic.rejoin("support:org:org-1");
    unmount();
  });

  it("waits for an organization and keeps load errors", async () => {
    const load = vi.fn(() => Promise.reject(new Error("offline")));
    mount(
      createInboxController({
        auth: fakeAuth(),
        ports: { topic: fakeTopic().port },
        organizationId: null,
        load,
      }),
    ).unmount();
    expect(load).not.toHaveBeenCalled();

    const { view, unmount } = mount(
      createInboxController({
        auth: fakeAuth(),
        ports: { topic: fakeTopic().port },
        organizationId: "org-1",
        load,
      }),
    );

    await flush();
    expect(view().error).toEqual(new Error("offline"));
    unmount();
  });
});

describe("createConversationController", () => {
  it("tracks messages and other people's typing, and sends the caller's", async () => {
    vi.useFakeTimers();
    const topic = fakeTopic();
    let rows = ["m1"];

    const { view, unmount } = mount(
      createConversationController({
        auth: fakeAuth(),
        ports: { topic: topic.port },
        conversationId: "c1",
        load: async () => rows,
        typingMs: 20,
      }),
    );

    await vi.advanceTimersByTimeAsync(0);
    expect(view().items).toEqual(["m1"]);
    topic.emit("inbox:c1", "typing", { user_id: OTHER });
    topic.emit("inbox:c1", "typing", { user_id: USER });
    topic.emit("inbox:c1", "typing", "junk");
    topic.emit("inbox:c1", "typing", {});
    expect(view().typing).toEqual([OTHER]);
    topic.emit("inbox:c1", "typing", { user_id: OTHER, typing: false });
    expect(view().typing).toEqual([]);
    topic.emit("inbox:c1", "typing", { user_id: OTHER, typing: true });
    topic.emit("inbox:c1", "typing", { user_id: OTHER });
    await vi.advanceTimersByTimeAsync(25);
    expect(view().typing).toEqual([]);

    view().setTyping(true);
    expect(topic.joined[0]?.sent).toEqual([
      { event: "typing", payload: { user_id: USER, typing: true } },
    ]);
    rows = ["m1", "m2"];
    topic.emit("inbox:c1", "message");
    topic.rejoin("inbox:c1");
    await vi.advanceTimersByTimeAsync(0);
    expect(view().items).toEqual(["m1", "m2"]);
    topic.emit("inbox:c1", "typing", { user_id: OTHER });
    unmount();
    expect(view().typing).toEqual([]);
    view().setTyping(false);
    expect(topic.joined[0]?.sent).toHaveLength(1);
  });

  it("waits for a conversation and a user", async () => {
    const topic = fakeTopic();
    mount(
      createConversationController({
        auth: fakeAuth(),
        ports: { topic: topic.port },
        conversationId: null,
        load: async () => [],
      }),
    ).unmount();
    mount(
      createConversationController({
        auth: fakeAuth(SIGNED_OUT),
        ports: { topic: topic.port },
        conversationId: "c1",
        load: async () => [],
      }),
    ).unmount();
    await flush();
    expect(topic.joined).toEqual([]);
  });
});

describe("createInboxWidgetController", () => {
  it("opens on the first message, remembers it and sends into it", async () => {
    const topic = fakeTopic();
    const storage = memoryStorage();
    const open = vi.fn(async () => "c9");
    const send = vi.fn(async () => undefined);
    const load = vi.fn(async (id: string) => [`${id}:m`]);

    const { view, unmount } = mount(
      createInboxWidgetController({
        auth: fakeAuth(),
        ports: { topic: topic.port, storage },
        open,
        send,
        load,
      }),
    );

    await flush();
    expect(view()).toMatchObject({ conversationId: null, items: undefined });
    await view().submit("hello");
    await flush();
    expect(await storage.get("better-supabase:inbox-widget")).toBe("c9");
    expect(view()).toMatchObject({ conversationId: "c9", items: ["c9:m"] });
    expect(topic.open()).toEqual(["inbox:c9"]);
    view().setTyping(true);
    expect(topic.joined.at(-1)?.sent).toHaveLength(1);
    await view().submit("again");
    expect(send).toHaveBeenCalledWith("c9", "again");
    await view().refresh();
    expect(load).toHaveBeenCalledTimes(3);

    view().reset();
    await flush();
    expect(await storage.get("better-supabase:inbox-widget")).toBeNull();
    expect(view().conversationId).toBeNull();
    expect(topic.open()).toEqual([]);
    unmount();
  });

  it("resumes a stored conversation once and works without storage", async () => {
    const topic = fakeTopic();
    const storage = memoryStorage({ widget: "c3" });
    const load = vi.fn(async () => ["x"]);

    const options = {
      auth: fakeAuth(),
      open: async () => "c4",
      send: async () => undefined,
      load,
    };

    const controller = createInboxWidgetController({
      ...options,
      ports: { topic: topic.port, storage },
      storageKey: "widget",
      topic: "support",
    });

    const first = mount(controller);
    await flush();
    expect(controller.getSnapshot().conversationId).toBe("c3");
    expect(load).toHaveBeenCalledWith("c3");
    expect(topic.open()).toEqual(["support:c3"]);
    first.unmount();
    mount(controller).unmount();
    expect(topic.joined).toHaveLength(2);

    const bare = mount(
      createInboxWidgetController({
        ...options,
        ports: { topic: topic.port, storage },
        storageKey: null,
      }),
    );

    await flush();
    expect(bare.view().conversationId).toBeNull();
    await bare.view().submit("hi");
    expect(bare.view().conversationId).toBe("c4");
    bare.view().reset();
    bare.unmount();
    expect(await storage.get("widget")).toBe("c3");

    const none = mount(
      createInboxWidgetController({ ...options, ports: { topic: topic.port } }),
    );

    await none.view().submit("hey");
    expect(none.view().conversationId).toBe("c4");
    none.unmount();
  });
});
