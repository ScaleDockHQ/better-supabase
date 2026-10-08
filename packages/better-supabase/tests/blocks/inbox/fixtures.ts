import { vi } from "vitest";

import type { BlockTransport } from "../../../src/blocks/inbox/index.ts";

export const AT = "2026-01-01T00:00:00Z";

export const inboxRow = {
  id: "i1",
  tenant_id: "org",
  name: "Support",
  channel: "whatsapp",
  channel_address: "+3100",
  installation_id: null,
  bot_mode: "bot",
  settings: { tone: "calm" },
  created_at: AT,
  archived_at: null,
};

export const contactRow = {
  id: "ct1",
  tenant_id: "org",
  user_id: null,
  name: "Ada",
  email: "ada@example.test",
  phone: null,
  avatar_url: null,
  metadata: { plan: "pro" },
};

export const conversationRow = {
  id: "c1",
  tenant_id: "org",
  inbox_id: "i1",
  contact_id: "ct1",
  subject: "Help",
  status: "open",
  priority: "high",
  assignee_id: null,
  team_id: null,
  bot_mode: "bot",
  thread_id: "whatsapp:+3100:+3199",
  snoozed_until: null,
  last_message_at: AT,
  last_message_preview: "hi",
  first_response_at: null,
  resolved_at: null,
  metadata: {},
  created_at: AT,
  contact: contactRow,
  inbox: { id: "i1", name: "Support", channel: "whatsapp" },
  last_read_at: null,
  unread: true,
};

export const messageRow = {
  id: "m1",
  conversation_id: "c1",
  direction: "inbound",
  kind: "message",
  author_type: "contact",
  author_id: "ct1",
  body: "hi",
  format: "text",
  attachments: [
    { path: "org/c1/a.png", name: "a.png", content_type: "image/png", size: 3 },
  ],
  reactions: { "👍": ["u1"] },
  mentions: [],
  external_id: "wamid.1",
  reply_to: null,
  metadata: {},
  created_at: AT,
  edited_at: null,
  deleted_at: null,
  delivery: null,
};

export const templateRow = {
  id: "t1",
  tenant_id: "org",
  inbox_id: null,
  name: "follow_up",
  channel: "whatsapp",
  language: "en",
  body: "Hello {{1}}",
  variables: ["1"],
  external_id: null,
};

export const storedEventRow = {
  id: "e1",
  adapter: "whatsapp",
  external_id: null,
  inbox_id: "i1",
  tenant_id: "org",
  headers: { "content-type": "application/json" },
  body: "{}",
  attempts: 0,
  received_at: AT,
};

/** A transport that answers each function from `answers` (a value, or a function of the arguments) and records the calls. */
export function fakeTransport(answers: Readonly<Record<string, unknown>>): {
  readonly transport: BlockTransport;
  readonly call: ReturnType<typeof vi.fn>;
} {
  const call = vi.fn(
    async (_schema: string, fn: string, args: Record<string, unknown>) => {
      if (!(fn in answers)) throw new Error(`unexpected ${fn}`);
      const answer = answers[fn];
      return typeof answer === "function" ? answer(args) : answer;
    },
  );
  return { transport: { call }, call };
}
