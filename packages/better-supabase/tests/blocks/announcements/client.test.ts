import { describe, expect, it, vi } from "vitest";

import type { Announcement } from "../../../src/blocks/announcements/announcements.ts";

import { createAnnouncementsController } from "../../../src/blocks/announcements/client.ts";
import {
  failed,
  fakeAuth,
  fakeTopic,
  flush,
  held,
  mount,
  resolved,
  SIGNED_OUT,
} from "../../fixtures/ports.ts";

// SAFETY: the controller reads only the ids.
const announcement = (id: string) => ({ id }) as unknown as Announcement;

describe("createAnnouncementsController", () => {
  it("loads for the tenant, reloads on the topic and dismisses", async () => {
    const topic = fakeTopic();

    const listActive = vi.fn(() =>
      resolved([announcement("a1"), announcement("a2")]),
    );

    const dismiss = vi.fn(() => resolved(true));

    const { view, unmount } = mount(
      createAnnouncementsController({
        client: { listActive, dismiss },
        auth: fakeAuth(),
        ports: { topic: topic.port },
        organizationId: "org-1",
      }),
    );

    await flush();
    expect(listActive).toHaveBeenCalledWith("org-1");
    expect(view().items).toHaveLength(2);
    expect(topic.open()).toEqual(["announcements"]);
    topic.emit("announcements", "announcement.published");
    topic.rejoin("announcements");
    await flush();
    expect(listActive).toHaveBeenCalledTimes(3);

    await view().dismiss("a1");
    expect(view().items?.map((each) => each.id)).toEqual(["a2"]);
    dismiss.mockReturnValue(failed("gone"));
    await view().dismiss("a2");
    expect(view().error?.message).toBe("gone");
    listActive.mockReturnValue(failed("down"));
    await view().refresh();
    expect(view().error?.message).toBe("down");
    expect(view().items).toHaveLength(1);
    unmount();
  });

  it("loads once without a topic, waits signed out, and drops a stale answer", async () => {
    const topic = fakeTopic();
    const answer = held([announcement("late")]);
    const listActive = vi.fn(() => answer.result);

    const controller = createAnnouncementsController({
      client: { listActive, dismiss: () => resolved(true) },
      auth: fakeAuth(),
      ports: { topic: topic.port },
      topic: null,
    });

    const first = mount(controller);
    await flush();
    expect(listActive).toHaveBeenCalledWith(null);
    first.unmount();
    answer.release();
    await flush();
    expect(controller.getSnapshot().items).toBeUndefined();
    expect(topic.joined).toEqual([]);

    const out = vi.fn(() => resolved([]));
    mount(
      createAnnouncementsController({
        client: { listActive: out, dismiss: () => resolved(true) },
        auth: fakeAuth(SIGNED_OUT),
        ports: { topic: topic.port },
      }),
    ).unmount();
    expect(out).not.toHaveBeenCalled();
  });
});
