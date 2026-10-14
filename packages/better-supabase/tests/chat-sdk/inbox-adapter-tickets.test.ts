import type { ChatInstance, Message } from "chat";

import { describe, expect, it, vi } from "vitest";

import type { InboxMessage } from "../../src/blocks/inbox/types.ts";
import type { IdentityTarget } from "../../src/core/contracts/authorization-hooks.ts";

import { createInbox } from "../../src/blocks/inbox/index.ts";
import { inboxAdapter, inboxIdentityOf } from "../../src/chat-sdk/index.ts";
import { fakeTransport, messageRow } from "../blocks/inbox/fixtures.ts";

function setup(target: IdentityTarget | null) {
  const { transport } = fakeTransport({ get_message: messageRow });
  const principalByIdentity = vi.fn(() => target);
  const ticketFor = vi.fn((userId: string) => `ticket:${userId}`);
  const adapter = inboxAdapter({
    inbox: createInbox({ transport }),
    identities: { principalByIdentity, ticketFor },
  });
  const seen: (string | undefined)[] = [];
  const messages: Message<InboxMessage>[] = [];
  const chat = {
    processMessage: (
      _adapter: unknown,
      _threadId: string,
      message: Message<InboxMessage>,
    ) => {
      seen.push(adapter.ticketOf(message));
      messages.push(message);
      return Promise.resolve();
    },
  };
  // SAFETY: dispatch only calls processMessage on the instance.
  void adapter.initialize(chat as unknown as ChatInstance);
  return { adapter, principalByIdentity, ticketFor, seen, messages };
}

const job = { conversation_id: "c1", message_id: "m1" };

describe("inboxAdapter identities", () => {
  it("runs a linked contact's message with a ticket for the user", async () => {
    const { adapter, principalByIdentity, ticketFor, seen } = setup({
      kind: "user",
      userId: "u1",
    });
    await adapter.dispatch(job);
    expect(principalByIdentity).toHaveBeenCalledWith(inboxIdentityOf("ct1"));
    expect(ticketFor).toHaveBeenCalledWith("u1");
    expect(seen).toEqual(["ticket:u1"]);
  });

  it("keeps an unlinked or contact-linked author a visitor", async () => {
    for (const target of [
      null,
      { kind: "contact" as const, contactId: "ct1" },
    ]) {
      const { adapter, ticketFor, seen } = setup(target);
      await adapter.dispatch(job);
      expect(ticketFor).not.toHaveBeenCalled();
      expect(seen).toEqual([undefined]);
    }
  });

  it("forgets the ticket once the handlers return", async () => {
    const { adapter, seen, messages } = setup({ kind: "user", userId: "u1" });
    await adapter.dispatch(job);
    expect(seen).toEqual(["ticket:u1"]);
    const [message] = messages;
    expect(message && adapter.ticketOf(message)).toBeUndefined();
  });
});
