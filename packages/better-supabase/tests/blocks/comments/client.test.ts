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
  const create = vi.fn(() => resolved(comment("c2", "New")));
  const edit = vi.fn(() => resolved(comment("c1", "Edited")));
  const remove = vi.fn(() => resolved(true));
  const resolve = vi.fn(() => resolved(comment("c1")));
  const pin = vi.fn(() => resolved(comment("c1")));

  const conversation = vi.fn(() =>
    resolved<string | undefined>(options.conversation),
  );

  const controller = createCommentsController({
    client: { list, create, edit, remove, resolve, pin, conversation },
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
    const { list, create, edit, remove, controller } = setup();
    const { view, unmount } = mount(controller);
    await flush();
    expect(list).toHaveBeenCalledWith(CUSTOMER, { limit: 20 });
    expect(view().comments?.map((each) => each.id)).toEqual(["c1"]);

    expect((await view().add("New", { parentId: "c1" })).ok).toBe(true);
    expect(create).toHaveBeenCalledWith(CUSTOMER, {
      parentId: "c1",
      body: "New",
    });
    expect(view().comments?.map((each) => each.id)).toEqual(["c1", "c2"]);

    expect((await view().edit("c1", { body: "Edited" })).ok).toBe(true);
    expect(view().comments?.[0]?.body).toBe("Edited");

    expect(await view().remove("c2")).toMatchObject({ ok: true, data: true });
    expect(remove).toHaveBeenCalledWith("c2");
    expect(list).toHaveBeenCalledTimes(2);
    expect(edit).toHaveBeenCalledOnce();
    unmount();
  });

  it("keeps errors from each call", async () => {
    const { list, create, edit, remove, controller } = setup();
    const { view, unmount } = mount(controller);
    await flush();
    create.mockReturnValue(failed("no create"));
    expect((await view().add("x")).ok).toBe(false);
    expect(view().error?.message).toBe("no create");
    edit.mockReturnValue(failed("no edit"));
    expect((await view().edit("c1", { body: "x" })).ok).toBe(false);
    expect(view().error?.message).toBe("no edit");
    remove.mockReturnValue(failed("no remove"));
    expect((await view().remove("c1")).ok).toBe(false);
    expect(view().error?.message).toBe("no remove");
    list.mockReturnValue(failed("down"));
    await view().refresh();
    expect(view().error?.message).toBe("down");
    unmount();
  });

  it("loads again for each ping on the conversation's topic and stops when signed out", async () => {
    const { topic, auth, list, controller } = setup({ conversation: "conv-1" });

    const { view, unmount } = mount(controller);
    await flush();
    expect(topic.open()).toEqual(["messages:conv-1"]);
    expect(view().status).toBe("subscribed");
    topic.emit("messages:conv-1", "message");
    topic.rejoin("messages:conv-1");
    expect(list).toHaveBeenCalledTimes(3);
    auth.set(SIGNED_OUT);
    expect(topic.open()).toEqual([]);
    unmount();
  });

  it("joins the topic once the first comment opens the conversation", async () => {
    const { topic, conversation, controller } = setup({ topic: "chat" });
    const { view, unmount } = mount(controller);
    await flush();
    expect(conversation).toHaveBeenCalledWith(CUSTOMER);
    expect(topic.open()).toEqual([]);
    await view().add("First");
    expect(topic.open()).toEqual(["chat:conv-1"]);
    await view().add("Second");
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
    expect((await view().resolve("c1")).ok).toBe(true);
    expect((await view().pin("c1", false)).ok).toBe(true);
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
    expect(await view().add("x")).toMatchObject({
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
    await view().add("New");
    slow.release();
    await flush();
    expect(view().comments?.map((each) => each.id)).toEqual(["c2"]);
    unmount();
  });
});
