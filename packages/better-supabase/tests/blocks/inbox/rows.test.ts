import { describe, expect, it } from "vitest";

import {
  contactOf,
  conversationOf,
  countsOf,
  messageOf,
  purgedOf,
  storedEventsOf,
} from "../../../src/blocks/inbox/rows.ts";

const at = "2026-10-22T10:00:00Z";

const conversation = {
  id: "c1",
  tenant_id: "t1",
  inbox_id: "i1",
  contact_id: "k1",
  thread_id: "th1",
  created_at: at,
};

describe("inbox rows", () => {
  it("leaves out a contact's tenant and metadata when the row has none", () => {
    expect(contactOf({ id: "k1" })).toStrictEqual({
      id: "k1",
      userId: null,
      name: null,
      email: null,
      phone: null,
      avatarUrl: null,
    });
  });

  it("reads a conversation's nested contact, inbox and unread flag", () => {
    const row = conversationOf({
      ...conversation,
      contact: { id: "k1", tenant_id: "t1", metadata: { vip: true } },
      inbox: { id: "i1", name: "Support", channel: "email" },
      unread: true,
    });

    expect(row.contact).toMatchObject({
      tenant: "t1",
      metadata: { vip: true },
    });
    expect(row.inbox).toStrictEqual({
      id: "i1",
      name: "Support",
      channel: "email",
    });
    expect(row.unread).toBe(true);
  });

  it("returns null for a missing contact and inbox, and no unread flag", () => {
    const row = conversationOf(conversation);

    expect(row.contact).toBeNull();
    expect(row.inbox).toBeNull();
    expect("unread" in row).toBe(false);
  });

  it("reads a message's delivery, and null for a delivery that is not a row", () => {
    const base = {
      id: "m1",
      tenant_id: "t1",
      conversation_id: "c1",
      created_at: at,
    };

    expect(
      messageOf({
        ...base,
        delivery: { channel: "email", status: "bounced", error: "full" },
      }).delivery,
    ).toStrictEqual({ channel: "email", status: "queued", error: "full" });
    expect(messageOf({ ...base, delivery: null }).delivery).toBeNull();
    expect("delivery" in messageOf(base)).toBe(false);
  });

  it("counts zero for missing totals", () => {
    expect(countsOf({})).toStrictEqual({
      open: 0,
      mine: 0,
      unassigned: 0,
      unread: 0,
    });
    expect(purgedOf({})).toStrictEqual({
      conversations: 0,
      messages: 0,
      attachments: [],
    });
  });

  it("reads purged files and skips entries that are not rows", () => {
    expect(
      purgedOf({
        conversations: 1,
        messages: 2,
        attachments: [{ bucket: "b", path: "p" }, "x"],
      }).attachments,
    ).toStrictEqual([{ bucket: "b", path: "p" }]);
  });

  it("counts zero attempts for a stored event without them", () => {
    const [event] = storedEventsOf([
      { id: "e1", adapter: "slack", body: "{}", received_at: at },
    ]);

    expect(event?.attempts).toBe(0);
    expect(event?.headers).toStrictEqual({});
  });
});
