import { describe, expect, it, vi } from "vitest";

import type { Comment } from "../../../src/blocks/comments/comments.ts";

import { createCommentsController } from "../../../src/blocks/comments/client.ts";
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

const comment = (id: string, body = id): Comment => ({
  id,
  organizationId: "org-1",
  subjectType: "customer",
  subjectId: "cu1",
  authorId: USER,
  body,
  document: null,
  mentions: [],
  parentId: undefined,
  createdAt: Temporal.Instant.from("2026-01-01T00:00:00Z"),
  editedAt: undefined,
  deletedAt: undefined,
  fields: {},
});

function setup(
  options: { topic?: string | null; organizationId?: string | null } = {},
) {
  const topic = fakeTopic();
  const auth = fakeAuth();
  const list = vi.fn(() => resolved<readonly Comment[]>([comment("c1")]));
  const create = vi.fn(() => resolved(comment("c2", "New")));
  const edit = vi.fn(() => resolved(comment("c1", "Edited")));
  const remove = vi.fn(() => resolved(true));
  const controller = createCommentsController({
    client: { list, create, edit, remove },
    auth,
    ports: { topic: topic.port },
    organizationId:
      options.organizationId === undefined ? "org-1" : options.organizationId,
    subjectType: "customer",
    subjectId: "cu1",
    limit: 20,
    ...(options.topic === undefined ? {} : { topic: options.topic }),
  });
  return { topic, auth, list, create, edit, remove, controller };
}

describe("createCommentsController", () => {
  it("loads the thread and keeps it current after writes", async () => {
    const { list, create, edit, remove, controller } = setup();
    const { view, unmount } = mount(controller);
    await flush();
    expect(list).toHaveBeenCalledWith("org-1", "customer", "cu1", {
      limit: 20,
    });
    expect(view().comments?.map((each) => each.id)).toEqual(["c1"]);

    expect((await view().add("New", { parentId: "c1" })).ok).toBe(true);
    expect(create).toHaveBeenCalledWith({
      parentId: "c1",
      organizationId: "org-1",
      subjectType: "customer",
      subjectId: "cu1",
      body: "New",
    });
    expect(view().comments?.map((each) => each.id)).toEqual(["c1", "c2"]);

    expect((await view().edit("c1", { body: "Edited" })).ok).toBe(true);
    expect(view().comments?.[0]?.body).toBe("Edited");

    expect(await view().remove("c2")).toMatchObject({ ok: true, data: true });
    expect(remove).toHaveBeenCalledWith("c2");
    expect(list).toHaveBeenCalledTimes(2);
    expect(edit).toHaveBeenCalledTimes(1);
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

  it("loads again for each message on the topic and stops when signed out", async () => {
    const { topic, auth, list, controller } = setup({ topic: "comments:cu1" });
    const { view, unmount } = mount(controller);
    await flush();
    expect(topic.open()).toEqual(["comments:cu1"]);
    expect(view().status).toBe("subscribed");
    topic.emit("comments:cu1", "INSERT");
    topic.rejoin("comments:cu1");
    expect(list).toHaveBeenCalledTimes(3);
    auth.set(SIGNED_OUT);
    expect(topic.open()).toEqual([]);
    unmount();
  });

  it("waits without an organization", async () => {
    const { list, create, controller } = setup({ organizationId: null });
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
    list.mockImplementationOnce(() => slow.result);
    const { view, unmount } = mount(controller);
    await flush();
    await view().add("New");
    slow.release();
    await flush();
    expect(view().comments?.map((each) => each.id)).toEqual(["c2"]);
    unmount();
  });
});
