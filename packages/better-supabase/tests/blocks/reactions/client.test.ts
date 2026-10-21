import { describe, expect, it, vi } from "vitest";

import type { ReactionCount } from "../../../src/blocks/reactions/reactions.ts";
import type { SubjectRef } from "../../../src/schema/types.ts";

import { createReactionsController } from "../../../src/blocks/reactions/client.ts";
import {
  failed,
  fakeAuth,
  fakeTopic,
  flush,
  held,
  mount,
  resolved,
} from "../../fixtures/ports.ts";

const count = (emoji: string, reacted: boolean): ReactionCount => ({
  emoji,
  count: 1,
  reacted,
  actors: [],
});

const comment = (id: string): SubjectRef => ({ type: "comment", id });

function setup(topicName?: string | null, tenant: string | null = "org-1") {
  const topic = fakeTopic();

  const summary = vi.fn((subjects: readonly SubjectRef[]) =>
    resolved(
      Object.fromEntries(
        subjects.map((subject) => [
          `${subject.type}:${subject.id}`,
          [count("+1", false)],
        ]),
      ),
    ),
  );

  const react = vi.fn(() => resolved([count("+1", true)]));

  const controller = createReactionsController({
    client: { summary, react },
    auth: fakeAuth(),
    ports: { topic: topic.port },
    tenant,
    subjects: [comment("c1")],
    ...(topicName === undefined ? {} : { topic: topicName }),
  });

  return { topic, summary, react, controller };
}

describe("createReactionsController", () => {
  it("loads the subjects and reloads for their reactions only", async () => {
    const { topic, summary, controller } = setup();
    const { view, unmount } = mount(controller);
    await flush();
    expect(view().reactions).toEqual({ "comment:c1": [count("+1", false)] });
    expect(topic.open()).toEqual(["reactions:org-1"]);

    topic.emit("reactions:org-1", "reaction.added", {
      subjectType: "task",
      subjectId: "c1",
    });
    topic.emit("reactions:org-1", "reaction.added", {
      subjectType: "comment",
      subjectId: "c9",
    });
    topic.emit("reactions:org-1", "reaction.added", {
      subjectType: "comment",
      subjectId: 7,
    });
    expect(summary).toHaveBeenCalledOnce();
    topic.emit("reactions:org-1", "reaction.added", {
      subjectType: "comment",
      subjectId: "c1",
    });
    topic.emit("reactions:org-1", "reaction.added", "opaque");
    topic.rejoin("reactions:org-1");
    expect(summary).toHaveBeenCalledTimes(4);

    view().setSubjects([comment("c1")]);
    expect(summary).toHaveBeenCalledTimes(4);
    view().setSubjects([comment("c1"), comment("c2")]);
    await flush();
    expect(summary).toHaveBeenLastCalledWith([comment("c1"), comment("c2")]);
    expect(Object.keys(view().reactions ?? {})).toEqual([
      "comment:c1",
      "comment:c2",
    ]);
    unmount();
    view().setSubjects([comment("c3")]);
    expect(summary).toHaveBeenCalledTimes(5);
  });

  it("toggles a reaction on and off and keeps errors", async () => {
    const { react, summary, controller } = setup(null);
    const { view, unmount } = mount(controller);
    await flush();
    await view().toggle(comment("c1"), "+1");
    expect(react).toHaveBeenLastCalledWith(comment("c1"), "+1", {
      present: true,
    });
    expect(view().reactions?.["comment:c1"]).toEqual([count("+1", true)]);
    await view().toggle(comment("c1"), "+1");
    expect(react).toHaveBeenLastCalledWith(comment("c1"), "+1", {
      present: false,
    });
    react.mockReturnValue(failed("denied"));
    await view().toggle(comment("c1"), "+1");
    expect(view().error?.message).toBe("denied");
    summary.mockReturnValue(failed("down"));
    await view().refresh();
    expect(view().error?.message).toBe("down");
    unmount();
  });

  it("drops an answer a newer load overtook", async () => {
    const { summary, controller } = setup(null);
    const slow = held({ old: [] });
    summary.mockReturnValueOnce(slow.result);
    const { view, unmount } = mount(controller);
    await flush();
    await view().refresh();
    slow.release();
    await flush();
    expect(Object.keys(view().reactions ?? {})).toEqual(["comment:c1"]);
    unmount();
  });

  it("waits without a tenant", async () => {
    const { topic, summary, controller } = setup(undefined, null);
    const { view, unmount } = mount(controller);
    await flush();
    await view().refresh();
    expect(summary).not.toHaveBeenCalled();
    expect(topic.open()).toEqual([]);
    expect(view().reactions).toBeUndefined();
    unmount();
  });
});
