import { afterEach, describe, expect, it, vi } from "vitest";

import type {
  ConversationsControllerOptions,
  MessagesControllerOptions,
} from "../../../src/blocks/messaging/client.ts";
import type {
  ConversationSummary,
  Message,
} from "../../../src/blocks/messaging/index.ts";

import {
  createConversationsController,
  createMessagesController,
} from "../../../src/blocks/messaging/client.ts";
import {
  failed,
  fakeAuth,
  fakeTopic,
  flush,
  mount,
  OTHER,
  resolved,
  SIGNED_OUT,
  USER,
} from "../../fixtures/ports.ts";

afterEach(() => {
  vi.useRealTimers();
});

const at = (second: number) =>
  Temporal.Instant.fromEpochMilliseconds(second * 1000);

function message(
  id: string,
  second: number,
  extra: Partial<Message> = {},
): Message {
  // SAFETY: the controllers read only these fields of a message.
  return {
    id,
    conversationId: "c1",
    threadId: undefined,
    broadcast: false,
    authorId: OTHER,
    sentAt: at(second),
    createdAt: at(second),
    ...extra,
  } as Message;
}

function fakeClient(rows: Message[]) {
  const store = new Map(rows.map((row) => [row.id, row]));

  const client = {
    list: vi.fn(({ before }: { conversationId: string; before?: unknown }) =>
      resolved(before === undefined ? [...rows] : [message("m0", 0)]),
    ),
    replies: vi.fn(() =>
      resolved([message("r1", 5, { threadId: "m1", authorId: USER })]),
    ),
    get: vi.fn((id: string) => resolved(store.get(id))),
    send: vi.fn(
      ({
        message: input,
      }: {
        conversationId: string;
        message: { body: string; parentId?: string };
      }) =>
        resolved(
          message("s1", 9, {
            authorId: USER,
            ...(input.parentId === undefined
              ? {}
              : { threadId: input.parentId }),
          }),
        ),
    ),
    edit: vi.fn(() => failed<Message>("gone")),
    remove: vi.fn(() => resolved(true)),
    pin: vi.fn(() => resolved(message("m1", 1, { pinnedBy: USER }))),
    resolve: vi.fn(() => resolved(message("m1", 1))),
    markRead: vi.fn(() => resolved(at(1))),
  };

  return { client, store };
}

const options = (
  client: ReturnType<typeof fakeClient>["client"],
  topic: ReturnType<typeof fakeTopic>,
  extra: Partial<MessagesControllerOptions> = {},
): MessagesControllerOptions => ({
  client,
  auth: fakeAuth(),
  ports: { topic: topic.port },
  conversationId: "c1",
  ...extra,
});

describe("createMessagesController", () => {
  it("loads, merges pings, tracks typing and marks read", async () => {
    vi.useFakeTimers();

    const topic = fakeTopic();

    const { client, store } = fakeClient([message("m2", 2), message("m1", 1)]);

    const { view, unmount } = mount(
      createMessagesController(
        options(client, topic, { limit: 2, typingTimeout: 20 }),
      ),
    );

    await vi.advanceTimersByTimeAsync(0);
    expect(view().messages?.map((each) => each.id)).toEqual(["m1", "m2"]);
    expect(view().hasOlder).toBe(true);
    expect(topic.open()).toEqual(["messages:c1"]);
    expect(client.markRead).toHaveBeenCalledWith("c1", {});

    topic.emit("messages:c1", "typing", { userId: OTHER });
    topic.emit("messages:c1", "typing", { userId: USER });
    topic.emit("messages:c1", "typing", {});
    expect(view().typing).toEqual([OTHER]);
    await vi.advanceTimersByTimeAsync(25);
    expect(view().typing).toEqual([]);

    store.set("m3", message("m3", 3));
    store.set("t1", message("t1", 4, { threadId: "m1" }));
    store.set("x1", message("x1", 4, { conversationId: "c2" }));
    topic.emit("messages:c1", "typing", { userId: OTHER, typing: true });
    topic.emit("messages:c1", "message", { messageId: "m3" });
    topic.emit("messages:c1", "message", { messageId: "t1" });
    topic.emit("messages:c1", "message", { messageId: "nope" });
    topic.emit("messages:c1", "message", "junk");
    topic.emit("messages:c1", "updated", { messageId: "x1" });
    await vi.advanceTimersByTimeAsync(0);
    expect(view().messages?.map((each) => each.id)).toEqual(["m1", "m2", "m3"]);
    expect(view().typing).toEqual([]);

    await view().loadOlder();
    expect(view().messages?.[0]?.id).toBe("m0");
    expect(view().hasOlder).toBe(false);

    view().setTyping(true);
    view().setTyping(true);
    view().setTyping(false);
    expect(topic.joined[0]?.sent).toEqual([
      {
        event: "typing",
        payload: { conversationId: "c1", userId: USER, typing: true },
      },
      {
        event: "typing",
        payload: { conversationId: "c1", userId: USER, typing: false },
      },
    ]);

    expect((await view().send({ body: "hello" })).ok).toBe(true);
    expect(view().messages?.at(-1)?.id).toBe("s1");
    expect((await view().edit({ id: "m1", edition: { body: "x" } })).ok).toBe(
      false,
    );
    expect(view().error?.message).toBe("gone");
    expect((await view().pin({ id: "m1" })).ok).toBe(true);
    expect((await view().resolve({ id: "m1" })).ok).toBe(true);
    expect((await view().remove("m1")).ok).toBe(true);
    client.remove.mockReturnValueOnce(failed("denied"));
    expect((await view().remove("m1")).ok).toBe(false);

    topic.rejoin("messages:c1");
    topic.emit("messages:c1", "typing", { userId: OTHER });
    await vi.advanceTimersByTimeAsync(0);
    unmount();
    expect(view().typing).toEqual([]);
    view().setTyping(true);
    expect(topic.joined[0]?.sent).toHaveLength(3);
  });

  it("shows a thread's replies and replies into it", async () => {
    const topic = fakeTopic();
    const { client } = fakeClient([]);

    const { view, unmount } = mount(
      createMessagesController(
        options(client, topic, { threadId: "m1", markRead: false }),
      ),
    );

    await flush();
    expect(view().messages?.map((each) => each.id)).toEqual(["r1"]);
    expect(view().hasOlder).toBe(false);
    await view().loadOlder();
    expect(client.list).not.toHaveBeenCalled();
    await view().send({ body: "reply" });
    expect(client.send).toHaveBeenCalledWith("c1", {
      parentId: "m1",
      body: "reply",
    });
    await view().markRead();
    expect(client.markRead).toHaveBeenCalledWith("c1", { threadId: "m1" });
    unmount();
  });

  it("waits for a conversation and keeps load errors", async () => {
    const topic = fakeTopic();
    const { client } = fakeClient([]);

    const idle = mount(
      createMessagesController(
        options(client, topic, { conversationId: null }),
      ),
    );

    expect((await idle.view().send({ body: "x" })).ok).toBe(false);
    await idle.view().refresh();
    await idle.view().markRead();
    await idle.view().loadOlder();
    idle.unmount();

    mount(
      createMessagesController(
        options(client, topic, { auth: fakeAuth(SIGNED_OUT) }),
      ),
    ).unmount();
    expect(topic.joined).toEqual([]);

    client.list.mockReturnValue(failed("offline"));

    const { view, unmount } = mount(
      createMessagesController(options(client, topic)),
    );

    await flush();
    expect(view().error?.message).toBe("offline");
    unmount();
  });
});

describe("createConversationsController", () => {
  const summary = (id: string) =>
    // SAFETY: the controller reads only the id of a summary.
    ({ id }) as ConversationSummary;

  it("lists conversations and follows them for new messages", async () => {
    const topic = fakeTopic();
    let rows = [summary("c1"), summary("c2")];
    const conversations = vi.fn(() => resolved(rows));

    const { view, unmount } = mount(
      createConversationsController({
        client: { conversations },
        auth: fakeAuth(),
        ports: { topic: topic.port },
        enabled: true,
        kinds: ["channel"],
        limit: 10,
        watch: 1,
      }),
    );

    await flush();
    expect(view().conversations?.map((each) => each.id)).toEqual(["c1", "c2"]);
    expect(conversations).toHaveBeenCalledWith({
      kinds: ["channel"],
      limit: 10,
    });
    expect(topic.open()).toEqual(["messages:c1"]);

    rows = [summary("c2")];
    topic.emit("messages:c1", "typing");
    topic.emit("messages:c1", "message");
    await flush();
    expect(topic.open()).toEqual(["messages:c2"]);
    topic.rejoin("messages:c2");
    unmount();
    expect(topic.open()).toEqual([]);
  });

  it("waits until enabled and keeps errors", async () => {
    const conversations = vi.fn(() => failed<ConversationSummary[]>("nope"));

    const client = {
      conversations,
    } as ConversationsControllerOptions["client"];

    const idle = mount(
      createConversationsController({
        client,
        auth: fakeAuth(),
        ports: { topic: fakeTopic().port },
        enabled: false,
      }),
    );

    await idle.view().refresh();
    expect(conversations).not.toHaveBeenCalled();
    idle.unmount();

    const { view, unmount } = mount(
      createConversationsController({
        client,
        auth: fakeAuth(),
        ports: { topic: fakeTopic().port },
        enabled: true,
      }),
    );

    await flush();
    expect(view().error?.message).toBe("nope");
    unmount();
  });
});
