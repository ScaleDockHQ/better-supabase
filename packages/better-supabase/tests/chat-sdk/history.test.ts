import type { IdentityContext } from "chat";

import { describe, expect, it, vi } from "vitest";

import type {
  IdentityRef,
  IdentityTarget,
} from "../../src/core/contracts/authorization-hooks.ts";

import {
  chatHistory,
  chatHistoryContactKey,
  chatHistoryUserKey,
  eraseChatHistory,
} from "../../src/chat-sdk/index.ts";

function context(userId: string, adapter = "slack"): IdentityContext {
  // SAFETY: the resolver reads only the adapter name and the author's user id.
  return { adapter, author: { userId }, message: {} } as IdentityContext;
}

const links: Record<string, IdentityTarget> = {
  "U-alice": { kind: "user", userId: "alice" },
  "U-contact": { kind: "contact", contactId: "c1" },
};

const principalByIdentity = (identity: IdentityRef): IdentityTarget | null =>
  links[identity.value] ?? null;

describe("chatHistory", () => {
  it("keys the user scope by the linked user, not by the platform id", async () => {
    const config = chatHistory({ principalByIdentity, retention: "30d" });
    const identity = config.user?.identity;

    expect(await identity?.(context("U-alice"))).toBe("user:alice");
    expect(await identity?.(context("U-alice", "teams"))).toBe("user:alice");
    expect(config.user?.retention).toBe("30d");
  });

  it("stores nothing for an author without a link", async () => {
    const identity = chatHistory({ principalByIdentity }).user?.identity;

    expect(await identity?.(context("U-stranger"))).toBeNull();
  });

  it("keeps a contact's history only when asked", async () => {
    const off = chatHistory({ principalByIdentity }).user?.identity;

    const on = chatHistory({ principalByIdentity, contacts: true }).user
      ?.identity;

    expect(await off?.(context("U-contact"))).toBeNull();
    expect(await on?.(context("U-contact"))).toBe("contact:c1");
  });

  it("looks the link up in the message's workspace", async () => {
    const seen: IdentityRef[] = [];

    const identity = chatHistory({
      principalByIdentity: (ref) => {
        seen.push(ref);

        return null;
      },
      workspaceOf: () => "T1",
    }).user?.identity;

    await identity?.(context("U1"));

    expect(seen).toEqual([
      { kind: "chat", provider: "slack", value: "U1", workspace: "T1" },
    ]);
  });

  it("reads the resolver from the server's authorization hooks", async () => {
    const identity = chatHistory({
      server: {
        authorization: {
          apiVersion: 1,
          name: "t",
          identities: { principalByIdentity },
        },
      },
    }).user?.identity;

    expect(await identity?.(context("U-alice"))).toBe("user:alice");
  });

  it("leaves unset options out and passes the thread cache through", () => {
    const config = chatHistory({
      principalByIdentity,
      maxPerUser: false,
      thread: { maxMessages: 50 },
    });

    expect(config.user).not.toHaveProperty("retention");
    expect(config.user?.maxPerUser).toBe(false);
    expect(config.thread).toEqual({ maxMessages: 50 });
  });
});

describe("eraseChatHistory", () => {
  it("deletes the user's key and returns the count", async () => {
    const remove = vi.fn(() => Promise.resolve({ deleted: 3 }));
    const history = { user: { delete: remove } };

    // SAFETY: the test double has the one method eraseChatHistory calls.
    const api = history as never;

    expect(await eraseChatHistory(api, { userId: "alice" })).toEqual({
      deleted: 3,
    });
    expect(await eraseChatHistory(api, { contactId: "c1" })).toEqual({
      deleted: 3,
    });
    expect(remove.mock.calls).toEqual([
      [{ userKey: chatHistoryUserKey("alice") }],
      [{ userKey: chatHistoryContactKey("c1") }],
    ]);
  });
});
