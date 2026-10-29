import { describe, expect, it, vi } from "vitest";

import type { RecordRef } from "../../../src/schema/types.ts";

import {
  attachmentsTopic,
  createAttachmentListController,
} from "../../../src/blocks/attachments/list-controller.ts";
import {
  failed,
  fakeAuth,
  fakeTopic,
  flush,
  mount,
  resolved,
} from "../../fixtures/ports.ts";

const task: RecordRef = { type: "task", id: "t1" };

function setup(
  topicName?: string | null,
  tenant: string | null = "org-1",
  subject: RecordRef | null = task,
) {
  const topic = fakeTopic();
  const list = vi.fn(() => resolved([]));

  const controller = createAttachmentListController({
    client: { list },
    auth: fakeAuth(),
    ports: { topic: topic.port },
    tenant,
    subject,
    ...(topicName === undefined ? {} : { topic: topicName }),
  });

  return { topic, list, controller };
}

describe("attachmentsTopic", () => {
  it("names the tenant's topic", () => {
    expect(attachmentsTopic("org-1")).toBe("attachments:org-1");
    expect(attachmentsTopic("org-1", "files")).toBe("files:org-1");
  });
});

describe("createAttachmentListController", () => {
  it("lists the subject's files and reloads for that subject only", async () => {
    const { topic, list, controller } = setup();
    const { view, unmount } = mount(controller);
    await flush();
    expect(list).toHaveBeenLastCalledWith(task);
    expect(view().attachments).toEqual([]);
    expect(topic.open()).toEqual(["attachments:org-1"]);

    topic.emit("attachments:org-1", "changed", {
      subjectType: "task",
      subjectId: "t2",
    });
    topic.emit("attachments:org-1", "changed", {
      subjectType: "deal",
      subjectId: "t1",
    });
    expect(list).toHaveBeenCalledOnce();
    topic.emit("attachments:org-1", "changed", {
      subjectType: "task",
      subjectId: "t1",
    });
    topic.rejoin("attachments:org-1");
    expect(list).toHaveBeenCalledTimes(3);
    unmount();
    expect(topic.open()).toEqual([]);
  });

  it("listens on a renamed topic and reloads files without a subject", async () => {
    const { topic, list, controller } = setup("files", "org-1", null);
    const { unmount } = mount(controller);
    await flush();
    expect(topic.open()).toEqual(["files:org-1"]);
    topic.emit("files:org-1", "changed", {
      subjectType: "task",
      subjectId: "t1",
    });
    topic.emit("files:org-1", "changed", {
      subjectType: null,
      subjectId: null,
    });
    expect(list).toHaveBeenCalledTimes(2);
    unmount();
  });

  it("loads without listening when the topic or tenant is null", async () => {
    for (const [name, tenant] of [
      [null, "org-1"],
      [undefined, null],
    ] as const) {
      const { topic, list, controller } = setup(name, tenant);
      const { view, unmount } = mount(controller);
      await flush();
      expect(list).toHaveBeenCalledOnce();
      expect(topic.open()).toEqual([]);
      list.mockReturnValue(failed("down"));
      await view().refresh();
      expect(view().error?.message).toBe("down");
      unmount();
    }
  });
});
