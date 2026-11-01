import { describe, expect, it, vi } from "vitest";

import type {
  AiChatPage,
  AiChatRecord,
  AiStoredMessage,
} from "../../../src/blocks/ai-chat/ai-chat.ts";

import {
  createAiChatsController,
  createAiChatTreeController,
  createAiModelsController,
  createAiShareController,
} from "../../../src/blocks/ai-chat/client.ts";
import {
  failed,
  fakeAuth,
  fakeTopic,
  flush,
  held,
  mount,
  OTHER,
  resolved,
  SIGNED_OUT,
  signedIn,
  USER,
} from "../../fixtures/ports.ts";

// SAFETY: the controllers read only these fields.
const chat = (id: string, temporary = false) =>
  ({ id, temporary }) as unknown as AiChatRecord;

const message = (id: string) => ({ id }) as unknown as AiStoredMessage;

const page = (ids: readonly string[], next?: string): AiChatPage => ({
  items: ids.map((id) => chat(id)),
  next,
});

function chatsClient() {
  return {
    list: vi.fn((query: { readonly cursor?: string }) =>
      resolved(query.cursor === undefined ? page(["a"], "p2") : page(["b"])),
    ),
    create: vi.fn(() => resolved(chat("new"))),
    update: vi.fn((id: string) => resolved({ ...chat(id), title: "Renamed" })),
    remove: vi.fn(() => resolved(true)),
  };
}

describe("createAiChatsController", () => {
  it("pages, reloads every shown page and edits the list", async () => {
    const topic = fakeTopic();
    const chats = chatsClient();

    const { view, unmount } = mount(
      createAiChatsController({
        // SAFETY: the fake has the methods the controller calls.
        client: { chats: chats as never },
        auth: fakeAuth(),
        ports: { topic: topic.port },
        query: { organizationId: "org-1", limit: 1 },
      }),
    );

    await flush();
    expect(view()).toMatchObject({ hasMore: true });
    expect(topic.open()).toEqual([`ai-chats:${USER}`]);
    await view().loadMore();
    expect(view().items?.map((item) => item.id)).toEqual(["a", "b"]);
    expect(view().hasMore).toBe(false);
    await view().loadMore();
    topic.emit(`ai-chats:${USER}`, "chat.updated");
    await flush();
    expect(chats.list).toHaveBeenLastCalledWith({
      organizationId: "org-1",
      limit: 1,
      cursor: "p2",
    });
    expect(view().items).toHaveLength(2);

    expect((await view().create({ title: "x" }))?.id).toBe("new");
    expect(view().items?.[0]?.id).toBe("new");
    chats.create.mockReturnValue(resolved(chat("tmp", true)));
    await view().create();
    expect(view().items).toHaveLength(3);
    expect(
      (await view().update({ chatId: "a", patch: { title: "Renamed" } }))?.id,
    ).toBe("a");
    await view().remove("b");
    expect(view().items?.map((item) => item.id)).toEqual(["new", "a"]);
    chats.remove.mockReturnValue(failed("denied"));
    await view().remove("a");
    expect(view().error?.message).toBe("denied");
    unmount();
  });

  it("keeps errors of failed pages and clears on sign-out", async () => {
    const auth = fakeAuth();
    const topic = fakeTopic();
    const chats = chatsClient();

    const { view, unmount } = mount(
      createAiChatsController({
        client: { chats: chats as never },
        auth,
        ports: { topic: topic.port },
        topic: null,
      }),
    );

    await flush();
    expect(await view().create()).toBeUndefined();
    chats.list.mockReturnValueOnce(failed("no more"));
    await view().loadMore();
    expect(view().error?.message).toBe("no more");
    chats.list.mockReturnValueOnce(failed("down"));
    await view().refresh();
    expect(view().error?.message).toBe("down");

    const slow = held(page(["late"]));
    chats.list.mockReturnValueOnce(slow.result);
    const refreshing = view().refresh();
    auth.set(SIGNED_OUT);
    expect(view()).toMatchObject({ items: undefined, hasMore: false });
    slow.release();
    await refreshing;
    expect(view().items).toBeUndefined();
    await view().refresh();
    await view().loadMore();
    expect(topic.joined).toEqual([]);

    const write = held(chat("x"));
    chats.update.mockReturnValueOnce(write.result);
    auth.set(signedIn(OTHER));
    await flush();
    const updating = view().update({ chatId: "a", patch: {} });
    auth.set(signedIn(USER));
    write.release();
    await updating;
    await flush();
    expect(view().items?.some((item) => item.id === "x")).toBe(false);
    unmount();
  });
});

describe("createAiChatTreeController", () => {
  function messages() {
    return {
      path: vi.fn(({ chatId }: { chatId: string }) =>
        resolved([message(`${chatId}-u`)]),
      ),
      switchBranch: vi.fn(() => resolved("a2")),
      siblings: vi.fn(() => resolved([message("a1"), message("a2")])),
    };
  }

  it("follows the branch, steps between siblings and reloads on saves", async () => {
    const topic = fakeTopic();
    const calls = messages();

    const { view, unmount } = mount(
      createAiChatTreeController({
        client: { messages: calls },
        ports: { topic: topic.port },
        chatId: "c1",
      }),
    );

    await flush();
    expect(view().path?.map((item) => item.id)).toEqual(["c1-u"]);
    topic.emit("ai-chat:c1", "message.saved");
    topic.emit("ai-chat:c1", "leaf.changed");
    topic.emit("ai-chat:c1", "typing");
    topic.rejoin("ai-chat:c1");
    expect(calls.path).toHaveBeenCalledTimes(4);

    await view().step({ messageId: "a1", offset: 1 });
    expect(calls.switchBranch).toHaveBeenCalledExactlyOnceWith("c1", "a2");
    expect(calls.path).toHaveBeenLastCalledWith("c1", { leafId: "a2" });
    await view().step({ messageId: "a2", offset: 1 });
    await view().step({ messageId: "zz", offset: 0 });
    expect(calls.switchBranch).toHaveBeenCalledExactlyOnceWith("c1", "a2");

    calls.siblings.mockReturnValue(failed("gone"));
    await view().step({ messageId: "a1", offset: 1 });
    expect(view().error?.message).toBe("gone");
    calls.switchBranch.mockReturnValue(failed("no branch"));
    await view().switchBranch("a1");
    expect(view().error?.message).toBe("no branch");
    calls.path.mockReturnValue(failed("down"));
    await view().refresh();
    expect(view().error?.message).toBe("down");
    unmount();
  });

  it("waits without a chat and drops answers after it stopped", async () => {
    const calls = messages();

    const idle = mount(
      createAiChatTreeController({
        client: { messages: calls },
        ports: { topic: fakeTopic().port },
        chatId: null,
      }),
    );

    await idle.view().refresh();
    await idle.view().switchBranch("a");
    await idle.view().step({ messageId: "a", offset: 1 });
    idle.unmount();
    expect(calls.path).not.toHaveBeenCalled();

    const branch = held("a2");
    calls.switchBranch.mockReturnValueOnce(branch.result);
    const siblings = held([message("a1"), message("a2")]);
    calls.siblings.mockReturnValueOnce(siblings.result);

    const controller = createAiChatTreeController({
      client: { messages: calls },
      ports: { topic: fakeTopic().port },
      chatId: "c1",
      topic: null,
    });

    const mounted = mount(controller);
    await flush();
    const switching = mounted.view().switchBranch("a2");
    const stepping = mounted.view().step({ messageId: "a1", offset: 1 });
    mounted.unmount();
    branch.release();
    siblings.release();
    await switching;
    await stepping;
    expect(calls.path).toHaveBeenCalledOnce();
  });
});

describe("createAiModelsController", () => {
  it("loads the allowed models and keeps errors", async () => {
    const allowed = vi.fn(() => resolved([{ id: "m1" }]));

    const { view, unmount } = mount(
      createAiModelsController({
        client: { models: { allowed: allowed as never } },
        organizationId: "org-1",
      }),
    );

    await flush();
    expect(allowed).toHaveBeenCalledWith("org-1");
    expect(view().models).toHaveLength(1);
    allowed.mockReturnValue(failed("down"));
    await view().refresh();
    expect(view().error?.message).toBe("down");
    unmount();

    const slow = held([]);

    const late = createAiModelsController({
      client: { models: { allowed: () => slow.result } },
    });

    mount(late).unmount();
    slow.release();
    await flush();
    expect(late.getSnapshot().models).toBeUndefined();
  });
});

describe("createAiShareController", () => {
  it("lists, creates and revokes share links", async () => {
    const shares = {
      list: vi.fn(() => resolved([{ id: "s1" }])),
      create: vi.fn(() => resolved({ id: "s2", token: "t" })),
      revoke: vi.fn(() => resolved(true)),
    };

    const { view, unmount } = mount(
      createAiShareController({
        client: { shares: shares as never },
        chatId: "c1",
      }),
    );

    await flush();
    expect(view().shares).toHaveLength(1);
    expect(await view().create("leaf")).toMatchObject({ token: "t" });
    expect(shares.create).toHaveBeenCalledWith("c1", "leaf");
    await view().revoke("s1");
    expect(shares.list).toHaveBeenCalledTimes(3);
    shares.revoke.mockReturnValue(failed("gone"));
    await view().revoke("s1");
    expect(view().error?.message).toBe("gone");
    shares.list.mockReturnValue(failed("down"));
    await view().create();
    expect(view().error?.message).toBe("down");
    unmount();

    const idle = mount(
      createAiShareController({
        client: { shares: shares as never },
        chatId: null,
      }),
    );

    expect(await idle.view().create()).toBeUndefined();
    idle.unmount();

    const slow = held([]);

    const late = createAiShareController({
      client: { shares: { ...shares, list: () => slow.result } as never },
      chatId: "c1",
    });

    mount(late).unmount();
    slow.release();
    await flush();
    expect(late.getSnapshot().shares).toBeUndefined();
  });
});
