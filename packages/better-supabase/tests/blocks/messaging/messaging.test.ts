import { describe, expect, it } from "vitest";

import {
  conversationTopic,
  createMessaging,
  messageChangeSchema,
  messageInputSchema,
} from "../../../src/blocks/messaging/index.ts";
import { fakeTransport } from "../inbox/fixtures.ts";

const AT = "2026-01-01T00:00:00Z";

const conversationRow = {
  id: "c1",
  tenant_id: "org",
  kind: "channel",
  access: "tenant",
  subject_type: null,
  subject_id: null,
  title: "launch",
  created_by: "u1",
  last_message_at: AT,
  archived_at: null,
  created_at: AT,
  updated_at: AT,
};

const messageRow = {
  id: "m1",
  tenant_id: "org",
  conversation_id: "c1",
  parent_id: null,
  thread_id: null,
  author_id: "u1",
  author: { id: "u1", name: "Ada", avatar_url: null },
  body: "Ship it @channel",
  document: { type: "doc" },
  mentions: ["u2"],
  mention_scope: "channel",
  broadcast: false,
  reply_count: "2",
  last_reply_at: AT,
  reply_user_ids: ["u2"],
  pinned_at: null,
  pinned_by: null,
  resolved_at: null,
  resolved_by: null,
  scheduled_for: null,
  sent_at: AT,
  edited_at: null,
  deleted_at: null,
  created_at: AT,
  attachments: [
    {
      id: "f1",
      name: "a.png",
      mimeType: "image/png",
      size: 10,
      status: "ready",
    },
  ],
  reactions: [{ emoji: "👍", count: 1, reacted: true, actors: ["u2"] }],
  fields: { priority: "high" },
};

const answers = {
  open_conversation: conversationRow,
  add_conversation_members: 2,
  remove_conversation_member: true,
  archive_conversation: true,
  list_conversations: [
    {
      ...conversationRow,
      kind: "subject",
      access: "subject",
      subject_type: "customer",
      subject_id: "cu1",
      unread: 3,
      mentions: 1,
      lastReadAt: AT,
      notify: "mentions",
    },
  ],
  unread_counts: { c1: { unread: 3, mentions: "1" } },
  mark_read: AT,
  set_conversation_notify: true,
  set_typing: true,
  follow: true,
  can_conversation: true,
  send_message: messageRow,
  edit_message: { ...messageRow, edited_at: AT },
  delete_message: true,
  pin_message: { ...messageRow, pinned_at: AT, pinned_by: "u1" },
  resolve_message: { ...messageRow, resolved_at: AT, resolved_by: "u1" },
  list_messages: [messageRow],
  list_replies: [{ ...messageRow, id: "m2", parent_id: "m1", thread_id: "m1" }],
  get_message: (args: Record<string, unknown>) =>
    args["message"] === "m1" ? messageRow : null,
  list_message_edits: [
    {
      id: "e1",
      message_id: "m1",
      body: "Ship",
      document: null,
      edited_by: "u1",
      edited_at: AT,
    },
  ],
  list_pinned_messages: [],
  publish_due_messages: 4,
};

describe("createMessaging", () => {
  it("calls every function with snake_case arguments", async () => {
    const { transport, call } = fakeTransport(answers);
    const messaging = createMessaging({ transport, tenant: "org" });
    const at = Temporal.Instant.from(AT);
    const cursor = { sentAt: at, id: "m1" };

    const opened = await messaging
      .open({
        kind: "channel",
        title: "launch",
        access: "tenant",
        memberIds: ["u2"],
      })
      .orThrow();

    expect(opened).toMatchObject({
      id: "c1",
      organizationId: "org",
      kind: "channel",
      access: "tenant",
      subject: undefined,
      title: "launch",
    });
    expect(opened.lastMessageAt?.equals(at)).toBe(true);

    await messaging.openDirect(["u2"]).orThrow();
    await messaging.openDirect(["u2", "u3"]).orThrow();
    await messaging.openSubject({ type: "customer", id: "cu1" }).orThrow();
    expect(await messaging.addMembers("c1", ["u2", "u3"]).orThrow()).toBe(2);
    expect(await messaging.removeMember("c1", "u2").orThrow()).toBe(true);
    expect(await messaging.archive("c1").orThrow()).toBe(true);

    const [summary] = await messaging
      .conversations({ kinds: ["subject"], limit: 5 })
      .orThrow();

    expect(summary).toMatchObject({
      kind: "subject",
      subject: { type: "customer", id: "cu1" },
      unread: 3,
      mentions: 1,
      notify: "mentions",
    });
    await messaging.conversations().orThrow();
    expect(await messaging.unreadCounts().orThrow()).toEqual({
      c1: { unread: 3, mentions: 1 },
    });
    expect(
      (
        await messaging.markRead("c1", { threadId: "m1", readAt: at }).orThrow()
      ).equals(at),
    ).toBe(true);
    await messaging.markRead("c1").orThrow();
    await messaging.setNotify("c1", "none").orThrow();
    await messaging.typing("c1").orThrow();
    await messaging.follow({ conversationId: "c1" }).orThrow();
    await messaging.follow({ threadId: "m1" }, false).orThrow();
    expect(await messaging.can("c1", "send").orThrow()).toBe(true);

    const sent = await messaging
      .send("c1", {
        body: "Ship it @channel",
        document: { type: "doc" },
        mentionIds: ["u2"],
        parentId: "m0",
        broadcast: true,
        scheduledFor: at,
        attachmentIds: ["f1"],
      })
      .orThrow();

    expect(sent).toMatchObject({
      id: "m1",
      author: { id: "u1", name: "Ada" },
      mentionIds: ["u2"],
      mentionScope: "channel",
      replyCount: 2,
      attachments: [{ id: "f1", mimeType: "image/png", status: "ready" }],
      reactions: [{ emoji: "👍", count: 1, reacted: true }],
      fields: { priority: "high" },
    });
    await messaging.send("c1", { body: "plain" }).orThrow();
    await messaging
      .edit("m1", { body: "edited", document: null, mentionIds: [] })
      .orThrow();
    await messaging.edit("m1", { body: "edited" }).orThrow();
    expect(await messaging.remove("m1").orThrow()).toBe(true);
    expect((await messaging.pin("m1").orThrow()).pinnedBy).toBe("u1");
    expect((await messaging.resolve("m1", false).orThrow()).resolvedBy).toBe(
      "u1",
    );
    expect(
      await messaging.list("c1", { before: cursor, limit: 20 }).orThrow(),
    ).toHaveLength(1);
    await messaging.list("c1", { after: cursor }).orThrow();
    expect(
      (await messaging.replies("m1", { after: cursor, limit: 5 }).orThrow())[0]
        ?.threadId,
    ).toBe("m1");
    expect((await messaging.get("m1").orThrow())?.id).toBe("m1");
    expect(await messaging.get("nope").orThrow()).toBeUndefined();
    expect((await messaging.edits("m1").orThrow())[0]).toMatchObject({
      messageId: "m1",
      document: undefined,
      editedBy: "u1",
    });
    expect(await messaging.pinned("c1").orThrow()).toEqual([]);
    expect(await messaging.publishDue(10).orThrow()).toBe(4);
    await messaging.publishDue().orThrow();

    expect(call.mock.calls.map(([, fn, args]) => [fn, args])).toMatchSnapshot();
  });

  it("reads a record's backlinks, a page at a time", async () => {
    const { transport, call } = fakeTransport({
      list_record_mentions: [
        {
          message: messageRow,
          conversation: {
            id: "c1",
            kind: "channel",
            title: "launch",
            subject_type: null,
            subject_id: null,
          },
        },
        {
          message: { ...messageRow, id: "m2" },
          conversation: {
            id: "c2",
            kind: "subject",
            title: null,
            subject_type: "deal",
            subject_id: "d1",
          },
        },
      ],
    });

    const messaging = createMessaging({ transport, tenant: "org" });
    const deal = { type: "deal", id: "d9" };

    const mentions = await messaging.recordMentions(deal).orThrow();

    expect(mentions.map((mention) => mention.message.id)).toEqual(["m1", "m2"]);
    expect(mentions[0]?.conversation).toEqual({
      id: "c1",
      kind: "channel",
      title: "launch",
      subject: undefined,
    });
    expect(mentions[1]?.conversation).toEqual({
      id: "c2",
      kind: "subject",
      title: undefined,
      subject: { type: "deal", id: "d1" },
    });
    expect(mentions[0]?.message.fields).toEqual({ priority: "high" });

    await messaging
      .recordMentions(deal, {
        before: { sentAt: Temporal.Instant.from(AT), id: "m2" },
        limit: 5,
      })
      .orThrow();

    expect(call.mock.calls.map(([, fn, args]) => [fn, args])).toEqual([
      [
        "list_record_mentions",
        {
          subject_type: "deal",
          subject_id: "d9",
          before: null,
          before_id: null,
          max_rows: null,
        },
      ],
      [
        "list_record_mentions",
        {
          subject_type: "deal",
          subject_id: "d9",
          before: AT,
          before_id: "m2",
          max_rows: 5,
        },
      ],
    ]);
  });

  it("needs a tenant for the calls that take none", async () => {
    const { transport } = fakeTransport(answers);
    const messaging = createMessaging({ transport });

    expect((await messaging.conversations()).ok).toBe(false);
    expect(await messaging.can("c1", "read").orThrow()).toBe(true);
  });

  it("reads sparse rows and runs hooks", async () => {
    const seen: string[] = [];

    const { transport } = fakeTransport({
      ...answers,
      list_conversations: [{ ...conversationRow, notify: null }],
      list_messages: [
        {
          ...messageRow,
          body: null,
          document: null,
          mention_scope: null,
          fields: null,
          attachments: [{ id: "f1", name: "a", size: null, status: "pending" }],
          reactions: null,
        },
      ],
    });

    const messaging = createMessaging({
      transport,
      tenant: "org",
      logger: { debug() {}, info() {}, warn() {}, error() {} },
      hooks: {
        conversations: {
          before: (_args, { method }) => {
            seen.push(method);
          },
        },
        list: {
          after: (_result, _args, { method }) => {
            seen.push(method);
          },
        },
      },
    });

    const [summary] = await messaging.conversations().orThrow();
    const [message] = await messaging.list("c1").orThrow();

    expect(summary?.notify).toBe("all");
    expect(summary?.lastReadAt).toBeUndefined();
    expect(message).toMatchObject({
      body: "",
      document: undefined,
      mentionScope: undefined,
      fields: {},
      attachments: [{ id: "f1", mimeType: undefined, size: undefined }],
      reactions: [],
    });
    expect(seen).toEqual(["conversations", "list"]);
  });

  it("rejects a row of an unknown kind", async () => {
    const { transport } = fakeTransport({
      open_conversation: { ...conversationRow, kind: "nope" },
    });

    const messaging = createMessaging({ transport, tenant: "org" });

    expect((await messaging.open({ kind: "channel" })).ok).toBe(false);
  });
});

describe("conversationTopic", () => {
  it("names the private topic of a conversation", () => {
    expect(conversationTopic("c1")).toBe("messages:c1");
    expect(conversationTopic("c1", "chat")).toBe("chat:c1");
  });
});

describe("message schemas", () => {
  it("validate what send and edit take", async () => {
    const sent = await messageInputSchema["~standard"].validate({
      body: "hi",
      mentionIds: ["00000000-0000-4000-8000-000000000001"],
    });

    const edited = await messageChangeSchema["~standard"].validate({
      body: "",
    });

    expect(sent.issues).toBeUndefined();
    expect(edited.issues).toBeDefined();
  });
});
