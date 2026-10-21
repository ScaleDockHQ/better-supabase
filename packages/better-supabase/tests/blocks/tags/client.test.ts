import { describe, expect, it, vi } from "vitest";

import type { Tag } from "../../../src/blocks/tags/tags.ts";
import type { SubjectRef } from "../../../src/schema/types.ts";

import { createTagInputController } from "../../../src/blocks/tags/client.ts";
import {
  failed,
  fakeAuth,
  flush,
  held,
  mount,
  resolved,
} from "../../fixtures/ports.ts";

const tag = (id: string, name: string): Tag => ({
  id,
  name,
  slug: name.toLowerCase(),
  fields: {},
});

const CUSTOMER: SubjectRef = { type: "customer", id: "cu1" };

function setup(subject: SubjectRef | null = CUSTOMER) {
  const auth = fakeAuth();

  const forSubject = vi.fn((_subject: SubjectRef) =>
    resolved<readonly Tag[]>([tag("t1", "VIP")]),
  );

  const list = vi.fn((_kind?: string) =>
    resolved<readonly Tag[]>([tag("t1", "VIP"), tag("t2", "Churn")]),
  );

  const tagFn = vi.fn((_subject: SubjectRef, _tagId: string) => resolved(true));

  const untag = vi.fn((_subject: SubjectRef, _tagId: string) => resolved(true));

  const create = vi.fn((_kind: string, name: string) =>
    resolved<Tag>({ id: "t3", name, slug: name.toLowerCase(), fields: {} }),
  );

  const onChanged = vi.fn();

  const controller = createTagInputController({
    client: { forSubject, list, tag: tagFn, untag, create },
    auth,
    subject,
    kind: "customer",
    onChanged,
  });

  return { forSubject, list, tagFn, untag, create, onChanged, controller };
}

describe("createTagInputController", () => {
  it("loads the subject's tags and the tags of the kind", async () => {
    const { forSubject, list, controller } = setup();
    const { view, unmount } = mount(controller);
    await flush();
    expect(forSubject).toHaveBeenCalledWith(CUSTOMER);
    expect(list).toHaveBeenCalledWith("customer");
    expect(view().tags?.map((each) => each.id)).toEqual(["t1"]);
    expect(view().available?.map((each) => each.id)).toEqual(["t1", "t2"]);
    unmount();
  });

  it("adds a tag at once and takes it back when it fails", async () => {
    const { tagFn, onChanged, controller } = setup();
    const { view, unmount } = mount(controller);
    await flush();
    const write = held(true);
    tagFn.mockReturnValueOnce(write.result);
    const adding = view().add("t2");
    expect(view().tags?.map((each) => each.id)).toEqual(["t1", "t2"]);
    expect(view().pending).toEqual(["t2"]);
    write.release();
    expect((await adding).ok).toBe(true);
    expect(tagFn).toHaveBeenCalledWith(CUSTOMER, "t2");
    expect(onChanged).toHaveBeenCalledWith({
      kind: "added",
      tag: tag("t2", "Churn"),
      created: false,
    });

    tagFn.mockReturnValueOnce(failed("not allowed"));
    await view().remove("t2");
    expect((await view().add("t2")).ok).toBe(false);
    expect(view().tags?.map((each) => each.id)).toEqual(["t1"]);
    expect(view().error?.message).toBe("not allowed");

    expect(await view().add("nope")).toMatchObject({
      ok: false,
      error: { kind: "not_found" },
    });
    unmount();
  });

  it("removes a tag at once and puts it back when it fails", async () => {
    const { untag, onChanged, controller } = setup();
    const { view, unmount } = mount(controller);
    await flush();
    untag.mockReturnValueOnce(failed("gone"));
    expect((await view().remove("t1")).ok).toBe(false);
    expect(view().tags?.map((each) => each.id)).toEqual(["t1"]);
    expect(view().error?.message).toBe("gone");

    expect((await view().remove("t1")).ok).toBe(true);
    expect(view().tags).toEqual([]);
    expect(onChanged).toHaveBeenCalledWith({
      kind: "removed",
      tag: tag("t1", "VIP"),
    });
    expect(await view().remove("t1")).toMatchObject({ ok: true, data: false });
    unmount();
  });

  it("creates a tag by name, or adds the existing one", async () => {
    const { create, tagFn, onChanged, controller } = setup();
    const { view, unmount } = mount(controller);
    await flush();
    expect((await view().create("  churn ")).ok).toBe(true);
    expect(create).not.toHaveBeenCalled();
    expect(tagFn).toHaveBeenLastCalledWith(CUSTOMER, "t2");

    expect(await view().create("New")).toMatchObject({
      ok: true,
      data: { id: "t3", kind: "customer" },
    });
    expect(create).toHaveBeenCalledWith("customer", "New");
    expect(view().available?.map((each) => each.id)).toEqual([
      "t1",
      "t2",
      "t3",
    ]);
    expect(onChanged).toHaveBeenLastCalledWith(
      expect.objectContaining({ kind: "added", created: true }),
    );

    expect((await view().create("  ")).ok).toBe(false);
    create.mockReturnValueOnce(failed("no tags.manage"));
    expect((await view().create("Other")).ok).toBe(false);
    expect(view().error?.message).toBe("no tags.manage");
    expect(view().pending).toEqual([]);
    unmount();
  });

  it("keeps load and onChanged errors, and waits without a subject", async () => {
    const { forSubject, list, onChanged, controller } = setup();
    const { view, unmount } = mount(controller);
    await flush();
    forSubject.mockReturnValueOnce(failed("no customers.read"));
    await view().refresh();
    expect(view().error?.message).toBe("no customers.read");
    list.mockReturnValueOnce(failed("no tags.read"));
    await view().refresh();
    expect(view().error?.message).toBe("no tags.read");
    onChanged.mockRejectedValueOnce(new Error("hook failed"));
    await view().add("t2");
    expect(view().error?.message).toBe("hook failed");
    unmount();

    const idle = setup(null);
    const idleView = mount(idle.controller);
    await flush();
    expect(idle.forSubject).not.toHaveBeenCalled();
    expect((await idleView.view().create("x")).ok).toBe(false);
    expect((await idleView.view().remove("t1")).ok).toBe(false);
    await idleView.view().refresh();
    idleView.unmount();
  });
});
