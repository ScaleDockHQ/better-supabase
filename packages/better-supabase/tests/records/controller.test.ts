import { describe, expect, it, vi } from "vitest";

import type { RecordSummary } from "../../src/records/index.ts";
import type { RecordRef } from "../../src/schema/types.ts";

import { defineBlock } from "../../src/blocks/define-block.ts";
import {
  createRecordController,
  defineSection,
} from "../../src/records/index.ts";
import {
  failed,
  fakeAuth,
  fakeTopic,
  flush,
  held,
  mount,
  resolved,
  SIGNED_OUT,
} from "../fixtures/ports.ts";

const customer = { type: "customer", id: "7" };

function setup() {
  const notes = vi.fn((subject: RecordRef) => resolved([subject.id]));
  const files = vi.fn((_subject: RecordRef) => resolved(2));

  const notesBlock = defineBlock({
    name: "notes",
    category: "collaboration",
    sections: {
      notes: defineSection({
        permissions: { read: "read" },
        load: (_client: unknown, subject) => notes(subject),
        events: ["note.created"],
      }),
    },
  });

  const filesBlock = defineBlock({
    name: "files",
    category: "collaboration",
    sections: {
      files: defineSection({
        permissions: { read: "read" },
        load: (_client: unknown, subject) => files(subject),
        events: ["file.*"],
      }),
    },
  });

  return {
    notes,
    files,
    source: {
      blocks: { notes: notesBlock, files: filesBlock },
      clients: { notes: {}, files: {} },
    },
  };
}

const summaryOf = (title: string): RecordSummary => ({
  ...customer,
  title,
  url: "/customers/7",
  counts: { notes: 1 },
  unread: { notes: false },
});

describe("createRecordController", () => {
  it("loads every section and the summary on one topic", async () => {
    const { notes, files, source } = setup();
    const topic = fakeTopic();
    const summary = vi.fn(() => resolved(summaryOf("Acme")));

    const controller = createRecordController({
      source,
      auth: fakeAuth(),
      ports: { topic: topic.port },
      subject: customer,
      sections: ["notes", "files"],
      topic: "record:customer:7",
      summary: { summary },
      summaryOptions: { seenAt: null },
    });

    const { view, unmount } = mount(controller);

    await flush();

    expect(view().sections).toEqual({
      notes: { kind: "ok", data: ["7"] },
      files: { kind: "ok", data: 2 },
    });
    expect(view().summary?.title).toBe("Acme");
    expect(view().status).toBe("subscribed");
    expect(summary).toHaveBeenCalledWith(customer, ["notes", "files"], {
      seenAt: null,
    });
    expect(topic.open()).toEqual(["record:customer:7"]);

    notes.mockClear();
    files.mockClear();
    topic.emit("record:customer:7", "file.uploaded");
    await flush();

    expect(files).toHaveBeenCalledOnce();
    expect(notes).not.toHaveBeenCalled();
    expect(summary).toHaveBeenCalledTimes(2);

    files.mockClear();
    topic.emit("record:customer:7", "something.else");
    await flush();

    expect(notes).toHaveBeenCalledOnce();
    expect(files).toHaveBeenCalledOnce();

    topic.rejoin("record:customer:7");
    await flush();

    expect(notes).toHaveBeenCalledTimes(2);

    unmount();

    expect(topic.open()).toEqual([]);
  });

  it("keeps the summary error next to the sections", async () => {
    const { source } = setup();

    const controller = createRecordController({
      source,
      auth: fakeAuth(),
      ports: { topic: fakeTopic().port },
      subject: customer,
      sections: ["notes"],
      summary: { summary: () => failed("gone") },
    });

    const { view } = mount(controller);

    await flush();

    expect(view().error?.kind).toBe("not_found");
    expect(view().sections?.notes?.kind).toBe("ok");
  });

  it("refreshes only the named sections", async () => {
    const { notes, files, source } = setup();

    const controller = createRecordController({
      source,
      auth: fakeAuth(),
      ports: { topic: fakeTopic().port },
      subject: customer,
      sections: ["notes", "files"],
    });

    const { view } = mount(controller);

    await flush();
    notes.mockClear();
    files.mockClear();
    await view().refresh(["files"]);

    expect(files).toHaveBeenCalledOnce();
    expect(notes).not.toHaveBeenCalled();
  });

  it("drops a section load a newer load overtook", async () => {
    const { notes, source } = setup();
    const slow = held(["old"]);
    notes.mockReturnValueOnce(slow.result);

    const controller = createRecordController({
      source,
      auth: fakeAuth(),
      ports: { topic: fakeTopic().port },
      subject: customer,
      sections: ["notes"],
    });

    const { view } = mount(controller);

    await view().refresh(["notes"]);
    slow.release();
    await flush();

    expect(view().sections?.notes).toEqual({ kind: "ok", data: ["7"] });
  });

  it("drops a summary a newer load overtook", async () => {
    const { source } = setup();
    const slow = held(summaryOf("Old"));

    const summary = vi
      .fn()
      .mockReturnValueOnce(slow.result)
      .mockReturnValue(resolved(summaryOf("New")));

    const controller = createRecordController({
      source,
      auth: fakeAuth(),
      ports: { topic: fakeTopic().port },
      subject: customer,
      sections: [],
      summary: { summary },
    });

    const { view } = mount(controller);

    await view().refresh();
    slow.release();
    await flush();

    expect(view().summary?.title).toBe("New");
  });

  it("loads nothing without a subject or while signed out", async () => {
    const { notes, source } = setup();

    const empty = createRecordController({
      source,
      auth: fakeAuth(),
      ports: { topic: fakeTopic().port },
      subject: null,
      sections: ["notes"],
      summary: { summary: () => resolved(summaryOf("x")) },
    });

    const { view } = mount(empty);

    await view().refresh();
    await flush();

    expect(view().sections).toBeUndefined();
    expect(view().summary).toBeUndefined();

    mount(
      createRecordController({
        source,
        auth: fakeAuth(SIGNED_OUT),
        ports: { topic: fakeTopic().port },
        subject: customer,
        sections: ["notes"],
      }),
    );
    await flush();

    expect(notes).not.toHaveBeenCalled();
  });
});
