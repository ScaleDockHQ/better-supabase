import { describe, expect, it } from "vitest";

import {
  createInbox,
  INBOX_CHANNELS,
} from "../../../src/blocks/inbox/index.ts";
import {
  AT,
  contactRow,
  conversationRow,
  fakeTransport,
  inboxRow,
  messageRow,
  storedEventRow,
  templateRow,
} from "./fixtures.ts";

const answers = {
  create_inbox: inboxRow,
  update_inbox: { ...inboxRow, channel: "nope", bot_mode: "nope" },
  set_inbox_member: true,
  create_inbox_team: { id: "team1", name: "Tier 1" },
  set_inbox_team_member: true,
  upsert_contact: contactRow,
  start_conversation: conversationRow,
  list_inbox_conversations: [conversationRow],
  get_conversation: null,
  assign_conversation: { ...conversationRow, assignee_id: "u1" },
  set_conversation_status: { ...conversationRow, status: "resolved" },
  set_bot_mode: { ...conversationRow, bot_mode: "human" },
  mark_conversation_read: AT,
  set_typing: true,
  list_conversation_events: [
    {
      id: 1,
      type: "assigned",
      actor_id: "u1",
      data: { to: "u1" },
      created_at: AT,
    },
  ],
  inbox_counts: { open: 3, mine: 1, unassigned: 2, unread: 1 },
  send_inbox_message: {
    ...messageRow,
    delivery: { channel: "whatsapp", status: "sent", error: null },
  },
  list_inbox_messages: [messageRow],
  get_inbox_message: null,
  edit_inbox_message: { ...messageRow, body: "edited", edited_at: AT },
  react_to_inbox_message: [
    { emoji: "👍", count: 2, reacted: false, actors: ["u1", "bot"] },
  ],
  create_inbox_attachment: {
    id: "f2",
    bucket: "attachments",
    object_path: "org/conversation/c1/f2",
  },
  confirm_attachment: { id: "f2", status: "clean" },
  pending_inbox_files: [
    {
      id: "f3",
      tenant_id: "org",
      conversation_id: "c1",
      message_id: "m1",
      bucket: "attachments",
      object_path: "org/conversation/c1/f3",
      name: "photo.jpg",
      mime_type: null,
      source: {
        url: "https://cdn.test/photo.jpg",
        path: "org/c1/photo.jpg",
        bucket: "inbox-files",
        name: "photo.jpg",
        content_type: "image/jpeg",
        size: 9,
      },
    },
    {
      id: "f4",
      conversation_id: "c1",
      message_id: "m1",
      tenant_id: "org",
      bucket: "attachments",
      object_path: "p",
      name: "x",
      source: null,
    },
  ],
  inbox_file_failed: true,
  record_delivery: null,
  set_delivery_status: 2,
  upsert_message_template: templateRow,
  delete_message_template: true,
  record_inbound: {
    conversation_id: "c1",
    message_id: "m1",
    contact_id: "ct1",
    tenant_id: "org",
    created: true,
    duplicate: false,
  },
  store_inbound_event: { id: "e1", duplicate: false },
  set_inbound_event_status: true,
  pending_inbound_events: [storedEventRow],
  purge_inbound_events: 4,
  wake_snoozed_conversations: 1,
  purge_contact: {
    conversations: 2,
    messages: 5,
    attachments: [{ bucket: "inbox-files", path: "org/c1/photo.jpg" }, null],
  },
};

describe("createInbox", () => {
  it("calls every function with snake_case arguments", async () => {
    const { transport, call } = fakeTransport(answers);
    const inbox = createInbox({ transport, schema: "app" });
    const later = Temporal.Instant.from("2026-02-01T00:00:00Z");

    const created = await inbox.inboxes
      .create({ tenant: "org", name: "Support", channel: "whatsapp" })
      .orThrow();

    expect(created).toMatchObject({
      channel: "whatsapp",
      botMode: "bot",
      address: "+3100",
    });

    const updated = await inbox.inboxes
      .update("i1", {
        name: "Help",
        botMode: "paused",
        address: "+31",
        archived: true,
      })
      .orThrow();

    expect(updated).toMatchObject({ channel: "other", botMode: "human" });
    expect(await inbox.inboxes.setMember("i1", "u1", "lead").orThrow()).toBe(
      true,
    );
    expect(await inbox.inboxes.setMember("i1", "u1", null).orThrow()).toBe(
      true,
    );
    expect(await inbox.inboxes.createTeam("org", "Tier 1").orThrow()).toEqual({
      id: "team1",
      name: "Tier 1",
    });
    await inbox.inboxes.setTeamMember("team1", "u1").orThrow();

    const contact = await inbox.contacts
      .upsert("org", {
        name: "Ada",
        identity: { channel: "whatsapp", externalId: "+3199" },
      })
      .orThrow();

    expect(contact).toMatchObject({ name: "Ada", metadata: { plan: "pro" } });

    const open = await inbox.conversations
      .open("i1", { contact: { email: "ada@example.test" }, message: "hi" })
      .orThrow();

    expect(open).toMatchObject({
      priority: "high",
      unread: true,
      inbox: { channel: "whatsapp" },
      contact: { name: "Ada" },
    });
    await inbox.conversations.open("i1", {
      contact: "ct1",
      message: { body: "hi", format: "markdown" },
    });

    const [listed] = await inbox.conversations
      .list("org", {
        status: "all",
        assignee: "me",
        cursor: { id: "c0", lastMessageAt: later },
        limit: 10,
      })
      .orThrow();

    expect(listed?.lastMessageAt?.toString()).toBe(AT);
    expect(await inbox.conversations.get("c1").orThrow()).toBeNull();
    expect(
      (await inbox.conversations.assign("c1", { assigneeId: "u1" }).orThrow())
        .assigneeId,
    ).toBe("u1");
    await inbox.conversations.snooze("c1", later).orThrow();
    await inbox.conversations.resolve("c1").orThrow();
    await inbox.conversations.reopen("c1").orThrow();
    expect(
      (await inbox.conversations.handoff("c1", "asked").orThrow()).botMode,
    ).toBe("human");
    await inbox.conversations.setBotMode("c1", "bot").orThrow();
    expect(
      (await inbox.conversations.markRead("c1").orThrow()).toString(),
    ).toBe(AT);
    expect(await inbox.conversations.typing("c1").orThrow()).toBe(true);
    const [event] = await inbox.conversations.events("c1").orThrow();
    expect(event).toMatchObject({
      id: "1",
      type: "assigned",
      data: { to: "u1" },
    });
    expect(await inbox.conversations.counts("org").orThrow()).toEqual({
      open: 3,
      mine: 1,
      unassigned: 2,
      unread: 1,
    });

    const sent = await inbox.messages
      .send("c1", {
        body: "**hi**",
        format: "markdown",
        attachments: ["f2"],
        files: [
          { url: "https://cdn.test/a.png", contentType: "image/png", size: 1 },
        ],
        mentions: ["u2"],
        authorType: "bot",
        deliveredByCaller: true,
      })
      .orThrow();

    expect(sent.delivery).toEqual({
      channel: "whatsapp",
      status: "sent",
      error: null,
    });
    await inbox.messages.note("c1", "internal", { mentions: ["u2"] }).orThrow();

    const [message] = await inbox.messages
      .list("c1", { cursor: later, limit: 5 })
      .orThrow();

    expect(message).toMatchObject({
      attachments: [{ id: "f1", mimeType: "image/png", status: "clean" }],
      reactions: [{ emoji: "👍", count: 1, actors: ["u1"] }],
      externalId: "wamid.1",
      authorId: undefined,
      authorType: "contact",
    });
    expect(message?.delivery).toBeNull();
    expect(await inbox.messages.get("m1").orThrow()).toBeNull();
    expect(
      (
        await inbox.messages.edit("m1", "edited").orThrow()
      ).editedAt?.toString(),
    ).toBe(AT);
    await inbox.messages.remove("m1").orThrow();
    expect(
      await inbox.messages.react("m1", "👍", { actor: "bot" }).orThrow(),
    ).toEqual([
      { emoji: "👍", count: 2, reacted: false, actors: ["u1", "bot"] },
    ]);
    expect(
      await inbox.messages
        .createUpload("c1", { name: "a.png", mimeType: "image/png", size: 1 })
        .orThrow(),
    ).toEqual({
      id: "f2",
      bucket: "attachments",
      path: "org/conversation/c1/f2",
    });
    await inbox.messages.confirmUpload("f2").orThrow();

    const [pending, bare] = await inbox.files.pending(5).orThrow();

    expect(pending).toEqual({
      id: "f3",
      conversationId: "c1",
      messageId: "m1",
      tenant: "org",
      bucket: "attachments",
      path: "org/conversation/c1/f3",
      name: "photo.jpg",
      mimeType: undefined,
      source: {
        url: "https://cdn.test/photo.jpg",
        path: "org/c1/photo.jpg",
        bucket: "inbox-files",
        name: "photo.jpg",
        contentType: "image/jpeg",
        size: 9,
      },
    });
    expect(bare?.source).toEqual({});
    await inbox.files.stored("f3").orThrow();
    await inbox.files.failed("f4", "404").orThrow();

    await inbox.deliveries
      .record({ messageId: "m1", channel: "whatsapp", externalId: "w1" })
      .orThrow();
    expect(
      await inbox.deliveries
        .setStatus({ channel: "whatsapp", externalId: "w1", status: "read" })
        .orThrow(),
    ).toBe(2);

    expect(
      await inbox.templates
        .upsert("org", {
          name: "follow_up",
          channel: "whatsapp",
          body: "Hello {{1}}",
          variables: ["1"],
        })
        .orThrow(),
    ).toMatchObject({ language: "en", variables: ["1"] });
    expect(await inbox.templates.delete("t1").orThrow()).toBe(true);

    expect(
      await inbox.inbound
        .record({
          inboxId: "i1",
          threadId: "whatsapp:+3100:+3199",
          contact: { externalId: "+3199", name: "Ada" },
          message: { body: "hi", externalId: "wamid.2" },
        })
        .orThrow(),
    ).toMatchObject({ created: true, duplicate: false, tenant: "org" });
    expect(
      await inbox.inbound
        .store({ adapter: "whatsapp", body: "{}", headers: { a: "b" } })
        .orThrow(),
    ).toEqual({ id: "e1", duplicate: false });
    await inbox.inbound.setStatus("e1", "failed", "boom").orThrow();

    const [stored] = await inbox.inbound
      .pending({ limit: 5, maxAttempts: 3 })
      .orThrow();

    expect(stored).toMatchObject({
      adapter: "whatsapp",
      headers: { "content-type": "application/json" },
    });
    expect(
      await inbox.inbound.purge({ olderThan: 60, batch: 10 }).orThrow(),
    ).toBe(4);
    expect(await inbox.wakeSnoozed().orThrow()).toBe(1);
    expect(await inbox.purgeContact("ct1").orThrow()).toEqual({
      conversations: 2,
      messages: 5,
      attachments: [{ bucket: "inbox-files", path: "org/c1/photo.jpg" }],
    });

    for (const [schema] of call.mock.calls) {
      expect(schema).toBe("app");
    }

    expect(call.mock.calls.map(([, fn, args]) => [fn, args])).toMatchSnapshot();
  });

  it("returns errors as values", async () => {
    const { transport } = fakeTransport({});
    const inbox = createInbox({ transport });
    const result = await inbox.conversations.get("c1");
    expect(result.ok).toBe(false);
  });

  it("lists the channels", () => {
    expect(INBOX_CHANNELS).toContain("in_app");
  });

  it("schedules, lists, moves, cancels and publishes replies", async () => {
    const scheduledRow = {
      id: "s1",
      tenant_id: "org",
      conversation_id: "c1",
      author_id: "u1",
      input: {
        body: "Back tomorrow",
        format: "markdown",
        attachments: ["f1"],
        mentions: ["u2"],
        reply_to: "m1",
        metadata: { source: "composer" },
      },
      scheduled_for: AT,
      created_at: AT,
    };

    const { transport, call } = fakeTransport({
      schedule_inbox_message: scheduledRow,
      list_scheduled_inbox_messages: [
        scheduledRow,
        { ...scheduledRow, id: "s2", input: { format: "html" } },
      ],
      reschedule_inbox_message: scheduledRow,
      cancel_inbox_message: true,
      publish_due_inbox_messages: 2,
    });

    const inbox = createInbox({ transport });
    const at = Temporal.Instant.from(AT);

    const scheduled = await inbox.messages
      .schedule("c1", { body: "Back tomorrow", format: "markdown" }, at)
      .orThrow();

    expect(scheduled).toMatchObject({
      id: "s1",
      conversationId: "c1",
      authorId: "u1",
      body: "Back tomorrow",
      format: "markdown",
      attachments: ["f1"],
      mentions: ["u2"],
      replyTo: "m1",
      metadata: { source: "composer" },
    });
    expect(scheduled.scheduledFor.toString()).toBe(AT);

    const [, second] = await inbox.messages.scheduled().orThrow();
    expect(second).toMatchObject({
      id: "s2",
      body: "",
      format: null,
      attachments: [],
      replyTo: null,
    });
    await inbox.messages.scheduled("c1").orThrow();
    await inbox.messages.reschedule("s1", at).orThrow();
    await inbox.messages.cancelScheduled("s1").orThrow();
    expect(await inbox.publishDue(5).orThrow()).toBe(2);
    expect(call.mock.calls.map(([, fn, args]) => [fn, args])).toEqual([
      [
        "schedule_inbox_message",
        {
          conversation: "c1",
          input: { body: "Back tomorrow", format: "markdown" },
          scheduled_for: AT,
        },
      ],
      ["list_scheduled_inbox_messages", { conversation: null }],
      ["list_scheduled_inbox_messages", { conversation: "c1" }],
      ["reschedule_inbox_message", { scheduled: "s1", scheduled_for: AT }],
      ["cancel_inbox_message", { scheduled: "s1" }],
      ["publish_due_inbox_messages", { max_rows: 5 }],
    ]);
  });
});
