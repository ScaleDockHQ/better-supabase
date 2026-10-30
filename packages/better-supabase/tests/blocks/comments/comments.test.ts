import { describe, expect, it } from "vitest";

import { commentOf } from "../../../src/blocks/comments/comments.ts";
import {
  createComments,
  fileAnchor,
  mentionsIn,
} from "../../../src/blocks/comments/index.ts";

const ADA = "8c5a3d3e-0000-4000-8000-000000000001";
const BOB = "8c5a3d3e-0000-4000-8000-000000000002";

const PROJECT = { type: "project", id: "p1" };

const row = {
  id: "c1",
  tenant_id: "org-1",
  conversation_id: "conv-1",
  subject_type: "project",
  subject_id: "p1",
  author_id: ADA,
  body: "Hello",
  mentions: [BOB],
  parent_id: null,
  thread_id: null,
  anchor: null,
  sent_at: "2026-10-06T12:00:00Z",
  created_at: "2026-10-06T12:00:00Z",
  edited_at: null,
  deleted_at: null,
  task_id: null,
};

function fakeTransport(results: Record<string, unknown>) {
  const calls: [string, string, Record<string, unknown>][] = [];

  return {
    calls,
    transport: {
      call(
        schema: string,
        fn: string,
        args: Readonly<Record<string, unknown>>,
      ) {
        calls.push([schema, fn, { ...args }]);
        const result = results[fn];

        return result instanceof Error
          ? Promise.reject(result)
          : Promise.resolve(result);
      },
    },
  };
}

describe("mentionsIn", () => {
  it("returns each mentioned id once, in order", () => {
    expect(
      mentionsIn(
        `Hi @[Bob](${BOB.toUpperCase()}) and @[Ada](${ADA}), again @[Bob](${BOB}); not @Bob or @[x](42)`,
      ),
    ).toEqual([BOB, ADA]);
  });
});

describe("commentOf", () => {
  it("reads a message with its record and work item", () => {
    expect(
      commentOf({ ...row, task_id: "w1", anchor: { from: 1, to: 4 } }),
    ).toMatchObject({
      id: "c1",
      organizationId: "org-1",
      conversationId: "conv-1",
      subject: PROJECT,
      mentionIds: [BOB],
      anchor: { from: 1, to: 4 },
      taskId: "w1",
    });
    expect(commentOf(row).taskId).toBeUndefined();
  });
});

describe("createComments", () => {
  it("creates with the mentions from the body unless given", async () => {
    const fake = fakeTransport({ create_comment: row });

    const comments = createComments({
      transport: fake.transport,
      schema: "app",
      tenant: () => "org-1",
    });

    const comment = await comments
      .create(PROJECT, { body: `Hello @[Bob](${BOB})` })
      .orThrow();

    expect(comment).toMatchObject({
      id: "c1",
      subject: PROJECT,
      authorId: ADA,
      mentionIds: [BOB],
      parentId: undefined,
      editedAt: undefined,
    });
    expect(comment.sentAt?.toString()).toBe("2026-10-06T12:00:00Z");
    await comments
      .create(PROJECT, {
        body: "Reply",
        mentionIds: [],
        parentId: "c0",
        anchor: { field: "title" },
        attachmentIds: ["f1"],
      })
      .orThrow();
    expect(fake.calls).toEqual([
      [
        "app",
        "create_comment",
        {
          tenant: "org-1",
          subject_type: "project",
          subject_id: "p1",
          body: `Hello @[Bob](${BOB})`,
          attrs: { mentions: [BOB] },
          attachments: [],
        },
      ],
      [
        "app",
        "create_comment",
        {
          tenant: "org-1",
          subject_type: "project",
          subject_id: "p1",
          body: "Reply",
          attrs: { mentions: [], parentId: "c0", anchor: { field: "title" } },
          attachments: ["f1"],
        },
      ],
    ]);
  });

  it("edits through the messaging core and reads the comment back", async () => {
    const edited = { ...row, edited_at: "2026-10-06T12:05:00Z" };
    const fake = fakeTransport({ edit_message: {}, get_comment: edited });

    const comments = createComments({
      transport: fake.transport,
      mentionsOf: ({ document }) => (document ? [ADA] : []),
    });

    const comment = await comments
      .edit("c1", { body: "Changed", document: { type: "doc" } })
      .orThrow();

    expect(comment.editedAt?.toString()).toBe("2026-10-06T12:05:00Z");
    expect(fake.calls).toEqual([
      [
        "better_supabase",
        "edit_message",
        {
          message: "c1",
          body: "Changed",
          attrs: { mentions: [ADA], document: { type: "doc" } },
        },
      ],
      ["better_supabase", "get_comment", { message: "c1" }],
    ]);
  });

  it("returns not_found for a comment the caller can't read", async () => {
    const fake = fakeTransport({ get_comment: null });

    expect(
      await createComments({ transport: fake.transport }).get("c9"),
    ).toMatchObject({
      ok: false,
      error: { kind: "not_found", hint: "COMMENT_NOT_FOUND" },
    });
  });

  it("resolves, pins, lists edits and removes", async () => {
    const fake = fakeTransport({
      resolve_message: {},
      pin_message: {},
      get_comment: { ...row, resolved_at: "2026-10-06T13:00:00Z" },
      list_message_edits: [
        {
          id: "e1",
          message_id: "c1",
          body: "Helo",
          edited_by: ADA,
          edited_at: "2026-10-06T12:05:00Z",
        },
      ],
      delete_message: true,
    });

    const comments = createComments({ transport: fake.transport });

    expect(
      (await comments.resolve("c1").orThrow()).resolvedAt?.toString(),
    ).toBe("2026-10-06T13:00:00Z");
    await comments.resolve("c1", false).orThrow();
    await comments.pin("c1").orThrow();
    await comments.pin("c1", false).orThrow();
    expect(await comments.edits("c1").orThrow()).toMatchObject([
      { id: "e1", messageId: "c1", body: "Helo", editedBy: ADA },
    ]);
    expect(await comments.remove("c1").orThrow()).toBe(true);
    expect(
      fake.calls
        .filter(([, fn]) => fn !== "get_comment")
        .map(([, fn, args]) => [fn, args]),
    ).toEqual([
      ["resolve_message", { message: "c1", resolved: true }],
      ["resolve_message", { message: "c1", resolved: false }],
      ["pin_message", { message: "c1", pinned: true }],
      ["pin_message", { message: "c1", pinned: false }],
      ["list_message_edits", { message: "c1" }],
      ["delete_message", { message: "c1" }],
    ]);
  });

  it("turns a comment into a work item", async () => {
    const fake = fakeTransport({ assign_comment: "w1" });

    const comments = createComments({ transport: fake.transport });

    expect(
      await comments
        .assign("c1", {
          assigneeId: BOB,
          title: "Fix it",
          attrs: { priority: "high" },
        })
        .orThrow(),
    ).toBe("w1");
    await comments.assign("c1").orThrow();
    expect(fake.calls.map(([, , args]) => args)).toEqual([
      {
        message: "c1",
        assignee: BOB,
        attrs: { priority: "high", title: "Fix it" },
      },
      { message: "c1", assignee: null, attrs: {} },
    ]);

    const empty = fakeTransport({ assign_comment: null });
    expect(
      await createComments({ transport: empty.transport }).assign("c1"),
    ).toMatchObject({ ok: false });
  });

  it("finds or opens the record's conversation and moves the read marker", async () => {
    const fake = fakeTransport({
      comment_conversation: "conv-1",
      open_conversation: { id: "conv-1" },
      mark_read: "2026-10-06T14:00:00Z",
    });

    const comments = createComments({
      transport: fake.transport,
      tenant: "org-1",
    });

    expect(await comments.conversation(PROJECT).orThrow()).toBe("conv-1");
    expect(await comments.conversation(PROJECT, { open: true }).orThrow()).toBe(
      "conv-1",
    );
    expect(
      (
        await comments
          .markRead(PROJECT, {
            readAt: Temporal.Instant.from("2026-10-06T14:00:00Z"),
          })
          .orThrow()
      )?.toString(),
    ).toBe("2026-10-06T14:00:00Z");
    expect(fake.calls.map(([, fn, args]) => [fn, args])).toEqual([
      [
        "comment_conversation",
        { tenant: "org-1", subject_type: "project", subject_id: "p1" },
      ],
      [
        "open_conversation",
        {
          tenant: "org-1",
          kind: "subject",
          attrs: { subjectType: "project", subjectId: "p1" },
          members: [],
        },
      ],
      [
        "comment_conversation",
        { tenant: "org-1", subject_type: "project", subject_id: "p1" },
      ],
      [
        "mark_read",
        {
          conversation: "conv-1",
          thread: null,
          read_at: "2026-10-06T14:00:00Z",
        },
      ],
    ]);

    const none = fakeTransport({ comment_conversation: null });
    expect(
      await createComments({ transport: none.transport, tenant: "org-1" })
        .markRead(PROJECT)
        .orThrow(),
    ).toBeUndefined();
    expect(none.calls).toHaveLength(1);
  });

  it("lists a thread with deleted comments as placeholders", async () => {
    const fake = fakeTransport({
      list_comments: [
        row,
        { ...row, id: "c2", body: null, deleted_at: "2026-10-06T13:00:00Z" },
      ],
    });

    const comments = createComments({
      transport: fake.transport,
      tenant: "org-1",
    });

    const thread = await comments
      .list(PROJECT, {
        cursor: Temporal.Instant.from("2026-10-06T00:00:00Z"),
        cursorId: "c0",
        limit: 20,
      })
      .orThrow();

    expect(thread.map((comment) => [comment.id, comment.body])).toEqual([
      ["c1", "Hello"],
      ["c2", ""],
    ]);
    expect(thread[1]?.deletedAt).toBeDefined();
    expect(fake.calls[0]).toEqual([
      "better_supabase",
      "list_comments",
      {
        tenant: "org-1",
        subject_type: "project",
        subject_id: "p1",
        after: "2026-10-06T00:00:00Z",
        max_rows: 20,
        skip: undefined,
        after_id: "c0",
      },
    ]);
  });

  it("leaves deleted comments out with includeDeleted: false", async () => {
    const fake = fakeTransport({ list_comments: [row] });

    const comments = createComments({
      transport: fake.transport,
      tenant: "org-1",
    });

    await comments.list(PROJECT, { includeDeleted: false }).orThrow();
    expect(fake.calls[0]![2]).toMatchObject({ include_deleted: false });
  });

  it("pages by offset, counts comments per subject and copies a thread", async () => {
    const fake = fakeTransport({
      list_comments: [],
      comment_counts: { p1: 3, p9: "2" },
      copy_comments: 3,
    });

    const comments = createComments({
      transport: fake.transport,
      tenant: "org-1",
    });

    await comments.list(PROJECT, { offset: 40, limit: 20 });
    expect(fake.calls[0]![2]).toMatchObject({ skip: 40, max_rows: 20 });
    expect(
      await comments
        .counts(["p1", "p2", "p9", "p1"].map((id) => ({ type: "project", id })))
        .orThrow(),
    ).toEqual({ "project:p1": 3, "project:p2": 0, "project:p9": 2 });
    expect(fake.calls[1]).toEqual([
      "better_supabase",
      "comment_counts",
      {
        tenant: "org-1",
        subject_type: "project",
        subject_ids: ["p1", "p2", "p9"],
      },
    ]);
    expect(
      await comments
        .copy({ type: "quote", id: "q1" }, { type: "invoice", id: "i1" })
        .orThrow(),
    ).toBe(3);
    expect(fake.calls[2]![2]).toEqual({
      tenant: "org-1",
      from_type: "quote",
      from_id: "q1",
      to_type: "invoice",
      to_id: "i1",
    });
  });

  it("fails without a tenant and reads the author from the row", async () => {
    const fake = fakeTransport({
      list_comments: [
        { ...row, author: { id: ADA, name: "Ada", avatarUrl: null } },
      ],
    });

    const session: { tenant?: string } = {};

    const comments = createComments({
      transport: fake.transport,
      tenant: () => session.tenant,
    });

    expect(await comments.list(PROJECT)).toMatchObject({
      ok: false,
      error: { kind: "invalid_request", hint: "TENANT_REQUIRED" },
    });
    expect(fake.calls).toHaveLength(0);
    session.tenant = "org-2";
    const [comment] = await comments.list(PROJECT).orThrow();
    expect(comment?.author).toEqual({
      id: ADA,
      name: "Ada",
      avatarUrl: undefined,
    });
    expect(fake.calls[0]![2]).toMatchObject({ tenant: "org-2" });
  });

  it("maps database errors to DbError", async () => {
    const fake = fakeTransport({
      delete_message: Object.assign(new Error("permission denied"), {
        code: "42501",
      }),
    });

    expect(
      await createComments({ transport: fake.transport }).remove("c1"),
    ).toMatchObject({ ok: false, error: { kind: "forbidden" } });
  });
});

describe("comments.anchoredTo", () => {
  it("lists the comments anchored to a file", async () => {
    const file = "00000000-0000-4000-8000-0000000f1001";
    const anchor = fileAnchor(file, { page: 2 });
    const fake = fakeTransport({ list_file_comments: [{ ...row, anchor }] });
    const comments = createComments({ transport: fake.transport });

    const [comment] = await comments.anchoredTo(file, { limit: 5 }).orThrow();

    expect(fake.calls[0]?.slice(1)).toEqual([
      "list_file_comments",
      { attachment: file, max_rows: 5 },
    ]);
    expect(comment).toMatchObject({ anchor, subject: PROJECT });
  });
});
