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
    let rows = [{ id: "m1" }];
    const load = vi.fn(async () => rows);

    const { view, unmount } = mount(
      createConversationController({
        auth: fakeAuth(),
        ports: { topic: topic.port },
        conversationId: "c1",
        load,
        get: async () => null,
        typingMs: 20,
      }),
    );

    await vi.advanceTimersByTimeAsync(0);
    expect(view().items).toEqual([{ id: "m1" }]);
    expect(topic.open()).toEqual(["messages:c1"]);
    topic.emit("messages:c1", "typing", { userId: OTHER });
    topic.emit("messages:c1", "typing", { userId: USER });
    topic.emit("messages:c1", "typing", "junk");
    topic.emit("messages:c1", "typing", {});
    expect(view().typing).toEqual([OTHER]);
    topic.emit("messages:c1", "typing", { userId: OTHER, typing: false });
    expect(view().typing).toEqual([]);
    topic.emit("messages:c1", "typing", { userId: OTHER, typing: true });
    topic.emit("messages:c1", "typing", { userId: OTHER });
    await vi.advanceTimersByTimeAsync(25);
    expect(view().typing).toEqual([]);

    view().setTyping(true);
    expect(topic.joined[0]?.sent).toEqual([
      {
        event: "typing",
        payload: { conversationId: "c1", userId: USER, typing: true },
      },
    ]);
    rows = [{ id: "m1" }, { id: "m2" }];
    topic.rejoin("messages:c1");
    await vi.advanceTimersByTimeAsync(0);
    expect(view().items).toEqual(rows);
    expect(load).toHaveBeenCalledTimes(2);
    topic.emit("messages:c1", "typing", { userId: OTHER });
    unmount();
    expect(view().typing).toEqual([]);
    view().setTyping(false);
    expect(topic.joined[0]?.sent).toHaveLength(1);
  });

  it("fetches only the message a ping names", async () => {
    const topic = fakeTopic();
    const onEvent = vi.fn();

    const messages = new Map([
      ["m1", { id: "m1", body: "edited" }],
      ["m2", { id: "m2", body: "new" }],
    ]);

    const load = vi.fn(async () => [{ id: "m1", body: "first" }]);

    const get = vi.fn(async (id: string) => {
      if (id === "boom") {
        throw new Error("offline");
      }

      return messages.get(id) ?? null;
    });

    const { view, unmount } = mount(
      createConversationController({
        auth: fakeAuth(),
        ports: { topic: topic.port },
        conversationId: "c1",
        topic: "support",
        load,
        get,
        onEvent,
      }),
    );

    await flush();
    topic.emit("support:c1", "message", { messageId: "m1" });
    await flush();
    expect(view().items).toEqual([{ id: "m1", body: "edited" }]);
    topic.emit("support:c1", "message", { messageId: "m2" });
    topic.emit("support:c1", "message", { messageId: "gone" });
    await flush();
    expect(view().items).toEqual([
      { id: "m1", body: "edited" },
      { id: "m2", body: "new" },
    ]);
    topic.emit("support:c1", "read", { conversation_id: "c1" });
    topic.emit("support:c1", "conversation");
    expect(onEvent).toHaveBeenCalledWith("read", { conversation_id: "c1" });
    expect(onEvent).toHaveBeenCalledWith("conversation", {});
    topic.emit("support:c1", "message", { messageId: "boom" });
    await flush();
    expect(view().error).toEqual(new Error("offline"));
    expect(load).toHaveBeenCalledOnce();
    unmount();
  });

  it("adds a pinged message before the first load", async () => {
    const topic = fakeTopic();
    let release: (rows: { id: string }[]) => void = () => undefined;

    const { view, unmount } = mount(
      createConversationController({
        auth: fakeAuth(),
        ports: { topic: topic.port },
        conversationId: "c1",
        load: () =>
          new Promise<readonly { id: string }[]>((resolve) => {
            release = resolve;
          }),
        get: async (id) => ({ id }),
      }),
    );

    topic.emit("messages:c1", "message", { messageId: "m9" });
    await flush();
    expect(view().items).toEqual([{ id: "m9" }]);
    release([{ id: "m1" }]);
    await flush();
    unmount();
  });

  it("waits for a conversation and a user", async () => {
    const topic = fakeTopic();
    mount(
      createConversationController({
        auth: fakeAuth(),
        ports: { topic: topic.port },
        conversationId: null,
        load: async () => [],
        get: async () => null,
      }),
    ).unmount();
    mount(
      createConversationController({
        auth: fakeAuth(SIGNED_OUT),
        ports: { topic: topic.port },
        conversationId: "c1",
        load: async () => [],
        get: async () => null,
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
    const load = vi.fn(async (id: string) => [{ id: `${id}:m` }]);
    const get = vi.fn(async (id: string) => ({ id }));

    const { view, unmount } = mount(
      createInboxWidgetController({
        auth: fakeAuth(),
        ports: { topic: topic.port, storage },
        open,
        send,
        load,
        get,
      }),
    );

    await flush();
    expect(view()).toMatchObject({ conversationId: null, items: undefined });
    await view().submit("hello");
    await flush();
    expect(await storage.get("better-supabase:inbox-widget")).toBe("c9");
    expect(view()).toMatchObject({
      conversationId: "c9",
      items: [{ id: "c9:m" }],
    });
    expect(topic.open()).toEqual(["messages:c9"]);
    view().setTyping(true);
    expect(topic.joined.at(-1)?.sent).toHaveLength(1);
    await view().submit("again");
    expect(send).toHaveBeenCalledWith("c9", "again");
    expect(load).toHaveBeenCalledOnce();
    topic.emit("messages:c9", "message", { messageId: "m2" });
    await flush();
    expect(view().items).toEqual([{ id: "c9:m" }, { id: "m2" }]);
    await view().refresh();
    expect(load).toHaveBeenCalledTimes(2);

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
    const load = vi.fn(async () => [{ id: "x" }]);

    const options = {
      auth: fakeAuth(),
      open: async () => "c4",
      send: async () => undefined,
      load,
      get: async () => null,
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
