import { describe, expect, it } from "vitest";

import type { ConversationRow } from "@/features/inbox/inbox-types";

import {
  FIRST_RESPONSE_TARGET_MINUTES,
  slaStateOf,
  whatsappWindowOpen,
} from "@/features/inbox/inbox-types";

const NOW = Date.parse("2026-11-11T12:00:00Z");

const minutesAgo = (minutes: number): string =>
  new Date(NOW - minutes * 60_000).toISOString();

const row = (overrides: Partial<ConversationRow>): ConversationRow => ({
  id: "c1",
  subject: null,
  status: "open",
  snoozedUntil: null,
  botMode: "human",
  assigneeId: null,
  teamId: null,
  preview: null,
  lastMessageAt: null,
  unread: false,
  contactName: "Wile",
  contactReadAt: null,
  contactId: "p1",
  contactEmail: null,
  contactPhone: null,
  inboxId: "i1",
  inboxName: null,
  channel: "email",
  priority: "normal",
  firstResponseAt: null,
  lastInboundAt: null,
  createdAt: minutesAgo(1000),
  ...overrides,
});

describe("slaStateOf", () => {
  it("is met once staff answered or the contact has not written", () => {
    expect(slaStateOf(row({ firstResponseAt: minutesAgo(5) }), NOW)).toBe(
      "met",
    );
    expect(slaStateOf(row({}), NOW)).toBe("met");
  });

  it("warns at half the target and breaches at the target", () => {
    const at = (minutes: number) =>
      slaStateOf(row({ lastInboundAt: minutesAgo(minutes) }), NOW);

    expect(at(5)).toBe("ok");
    expect(at(FIRST_RESPONSE_TARGET_MINUTES / 2)).toBe("due");
    expect(at(FIRST_RESPONSE_TARGET_MINUTES)).toBe("breached");
  });

  it("stops the clock on a resolved conversation", () => {
    expect(
      slaStateOf(
        row({ status: "resolved", lastInboundAt: minutesAgo(500) }),
        NOW,
      ),
    ).toBe("met");
  });
});

describe("whatsappWindowOpen", () => {
  it("allows free replies on every other channel", () => {
    expect(whatsappWindowOpen(row({ channel: "email" }), NOW)).toBe(true);
  });

  it("closes 24 hours after the contact's last message", () => {
    const whatsapp = (minutes: number) =>
      row({ channel: "whatsapp", lastInboundAt: minutesAgo(minutes) });

    expect(whatsappWindowOpen(whatsapp(23 * 60), NOW)).toBe(true);
    expect(whatsappWindowOpen(whatsapp(25 * 60), NOW)).toBe(false);
  });

  it("is closed before the contact wrote", () => {
    expect(whatsappWindowOpen(row({ channel: "whatsapp" }), NOW)).toBe(false);
  });
});
