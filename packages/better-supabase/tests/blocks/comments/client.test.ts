import { describe, expect, it, vi } from "vitest";

import type { Comment } from "../../../src/blocks/comments/comments.ts";

import { createCommentsController } from "../../../src/blocks/comments/client.ts";
import { commentOf } from "../../../src/blocks/comments/comments.ts";
import {
  failed,
  fakeAuth,
  fakeTopic,
  flush,
  held,
  mount,
  resolved,
  SIGNED_OUT,
  USER,
} from "../../fixtures/ports.ts";

const CUSTOMER = { type: "customer", id: "cu1" };

const comment = (id: string, body = id): Comment =>
  commentOf({
    id,
    tenant_id: "org-1",
    conversation_id: "conv-1",
    subject_type: CUSTOMER.type,
    subject_id: CUSTOMER.id,
    author_id: USER,
    body,
    sent_at: "2026-01-01T00:00:00Z",
    created_at: "2026-01-01T00:00:00Z",
  });

function setup(
  options: {
    topic?: string | null;
    subject?: { type: string; id: string } | null;
    conversation?: string;
  } = {},
) {
  const topic = fakeTopic();
  const auth = fakeAuth();
  const list = vi.fn(() => resolved<readonly Comment[]>([comment("c1")]));
  const get = vi.fn((id: string) => resolved(comment(id, `Fetched ${id}`)));
  const create = vi.fn(() => resolved(comment("c2", "New")));
  const edit = vi.fn(() => resolved(comment("c1", "Edited")));
  const remove = vi.fn(() => resolved(true));
  const resolve = vi.fn(() => resolved(comment("c1")));
  const pin = vi.fn(() => resolved(comment("c1")));

  const conversation = vi.fn(() =>
    resolved<string | undefined>(options.conversation),
  );

  const controller = createCommentsController({
    client: { list, get, create, edit, remove, resolve, pin, conversation },
    auth,
    ports: { topic: topic.port },
    subject: options.subject === undefined ? CUSTOMER : options.subject,
    limit: 20,
    ...(options.topic === undefined ? {} : { topic: options.topic }),
  });

  return {
    topic,
    auth,
    list,
    get,
    create,
    edit,
    remove,
    resolve,
    pin,
    conversation,
    controller,
  };
}

describe("createCommentsController", () => {
  it("loads the thread and keeps it current after writes", async () => {
    const { list, get, create, edit, remove, controller } = setup();
    const { view, unmount } = mount(controller);
    await flush();
    expect(list).toHaveBeenCalledExactlyOnceWith(CUSTOMER, { limit: 20 });
    expect(view().comments?.map((each) => each.id)).toEqual(["c1"]);

    expect(
      (await view().add({ body: "New", draft: { parentId: "c1" } })).ok,
    ).toBe(true);
    expect(create).toHaveBeenCalledWith(CUSTOMER, {
      parentId: "c1",
      body: "New",
    });
    expect(view().comments?.map((each) => each.id)).toEqual(["c1", "c2"]);

    expect((await view().edit({ id: "c1", edit: { body: "Edited" } })).ok).toBe(
      true,
    );
    expect(view().comments?.[0]?.body).toBe("Edited");

    expect(await view().remove("c2")).toMatchObject({ ok: true, data: true });
    expect(remove).toHaveBeenCalledWith("c2");
    expect(get).toHaveBeenCalledWith("c2");
    expect(edit).toHaveBeenCalledOnce();
    unmount();
  });

  it("keeps errors from each call", async () => {
    const { list, create, edit, remove, controller } = setup();
    const { view, unmount } = mount(controller);
    await flush();
    create.mockReturnValue(failed("no create"));
    expect((await view().add({ body: "x" })).ok).toBe(false);
    expect(view().error?.message).toBe("no create");
    edit.mockReturnValue(failed("no edit"));
    expect((await view().edit({ id: "c1", edit: { body: "x" } })).ok).toBe(
      false,
    );
    expect(view().error?.message).toBe("no edit");
    remove.mockReturnValue(failed("no remove"));
    expect((await view().remove("c1")).ok).toBe(false);
    expect(view().error?.message).toBe("no remove");
    list.mockReturnValue(failed("down"));
    await view().refresh();
    expect(view().error?.message).toBe("down");
    unmount();
  });

  it("fetches the comment each ping names and stops when signed out", async () => {
    const { topic, auth, list, get, controller } = setup({
      conversation: "conv-1",
    });

    const { view, unmount } = mount(controller);
    await flush();
    expect(topic.open()).toEqual(["messages:conv-1"]);
    expect(view().status).toBe("subscribed");

    topic.emit("messages:conv-1", "message", {
      conversationId: "conv-1",
      messageId: "c3",
      threadId: "c1",
    });
    await flush();
    expect(get.mock.calls.map(([id]) => id)).toEqual(["c3", "c1"]);
    expect(view().comments?.map((each) => [each.id, each.body])).toEqual([
      ["c1", "Fetched c1"],
      ["c3", "Fetched c3"],
    ]);

    topic.emit("messages:conv-1", "message_updated", { messageId: "c1" });
    topic.emit("messages:conv-1", "message", {});
    topic.emit("messages:conv-1", "message", "not an object");
    await flush();
    expect(get).toHaveBeenCalledTimes(3);
    expect(list).toHaveBeenCalledOnce();

    get.mockReturnValueOnce(failed("gone"));
    topic.emit("messages:conv-1", "message_deleted", { messageId: "c3" });
    await flush();
    expect(view().comments).toHaveLength(2);
    expect(view().error).toBeUndefined();

    topic.rejoin("messages:conv-1");
    expect(list).toHaveBeenCalledTimes(2);
    auth.set(SIGNED_OUT);
    expect(topic.open()).toEqual([]);
    unmount();
  });

  it("leaves a ping before the first load to that load", async () => {
    const { topic, list, get, controller } = setup({ conversation: "conv-1" });
    const slow = held<readonly Comment[]>([comment("c1"), comment("c3")]);
    list.mockReturnValueOnce(slow.result);
    const { view, unmount } = mount(controller);
    await flush();
    topic.emit("messages:conv-1", "message", { messageId: "c3" });
    await flush();
    expect(get).toHaveBeenCalledWith("c3");
    expect(view().comments).toBeUndefined();
    slow.release();
    await flush();
    expect(view().comments?.map((each) => each.id)).toEqual(["c1", "c3"]);
    unmount();
  });

  it("joins the topic once the first comment opens the conversation", async () => {
    const { topic, conversation, controller } = setup({ topic: "chat" });
    const { view, unmount } = mount(controller);
    await flush();
    expect(conversation).toHaveBeenCalledWith(CUSTOMER);
    expect(topic.open()).toEqual([]);
    await view().add({ body: "First" });
    expect(topic.open()).toEqual(["chat:conv-1"]);
    await view().add({ body: "Second" });
    expect(topic.open()).toEqual(["chat:conv-1"]);
    unmount();
  });

  it("stays off Realtime with topic null, and resolves and pins", async () => {
    const { topic, conversation, resolve, pin, controller } = setup({
      topic: null,
      conversation: "conv-1",
    });

    const { view, unmount } = mount(controller);
    await flush();
    expect(conversation).not.toHaveBeenCalled();
    expect((await view().resolve({ id: "c1" })).ok).toBe(true);
    expect((await view().pin({ id: "c1", pinned: false })).ok).toBe(true);
    expect(resolve).toHaveBeenCalledWith("c1", undefined);
    expect(pin).toHaveBeenCalledWith("c1", false);
    expect(topic.open()).toEqual([]);
    unmount();
  });

  it("waits without a subject", async () => {
    const { list, create, controller } = setup({ subject: null });
    const { view, unmount } = mount(controller);
    await flush();
    await view().refresh();
    expect(await view().add({ body: "x" })).toMatchObject({
      ok: false,
      error: { kind: "invalid_input" },
    });
    expect(list).not.toHaveBeenCalled();
    expect(create).not.toHaveBeenCalled();
    unmount();
  });

  it("drops a load that a write overtook", async () => {
    const { list, controller } = setup();
    const slow = held<readonly Comment[]>([]);
    list.mockReturnValueOnce(slow.result);
    const { view, unmount } = mount(controller);
    await flush();
    await view().add({ body: "New" });
    slow.release();
    await flush();
    expect(view().comments?.map((each) => each.id)).toEqual(["c2"]);
    unmount();
  });
});
