import { describe, expect, it, vi } from "vitest";

import type {
  AuthorizationHooks,
  ChatActionHook,
  IdentityRef,
  IdentityTarget,
} from "../../src/core/contracts/authorization-hooks.ts";

import {
  approvalLink,
  approvalPrompt,
  botJobs,
  chatActionOf,
  chatActions,
  chatIdentityOf,
  resolveChatAuthor,
} from "../../src/chat-sdk/index.ts";

const ALICE: IdentityTarget = { kind: "user", userId: "alice" };
const linked = (identity: IdentityRef): IdentityTarget | null =>
  identity.value === "U-alice"
    ? ALICE
    : identity.value === "U-contact"
      ? { kind: "contact", contactId: "contact-1" }
      : null;
const author = (value: string): IdentityRef => ({
  kind: "chat",
  provider: "slack",
  value,
});
const server = (hooks: Partial<AuthorizationHooks>) => ({
  authorization: { apiVersion: 1, name: "test", ...hooks } as const,
});

describe("chatIdentityOf", () => {
  it("names the adapter as the provider", () => {
    expect(chatIdentityOf({ userId: "U1" }, { name: "slack" })).toEqual({
      kind: "chat",
      provider: "slack",
      value: "U1",
    });
    expect(chatIdentityOf({ userId: "U1" }, { name: "slack" }, "T1")).toEqual({
      kind: "chat",
      provider: "slack",
      value: "U1",
      workspace: "T1",
    });
  });
});

describe("resolveChatAuthor", () => {
  it("prefers the explicit resolver over the server hook", async () => {
    const hook = vi.fn(() => ALICE);
    expect(
      await resolveChatAuthor(author("U-x"), {
        principalByIdentity: () => null,
        server: server({ identities: { principalByIdentity: hook } }),
      }),
    ).toBeNull();
    expect(hook).not.toHaveBeenCalled();
    expect(
      await resolveChatAuthor(author("U-x"), {
        server: server({ identities: { principalByIdentity: hook } }),
      }),
    ).toEqual(ALICE);
  });

  it("is null without any resolver", async () => {
    expect(await resolveChatAuthor(author("U-alice"), {})).toBeNull();
    expect(
      await resolveChatAuthor(author("U-alice"), {
        server: { authorization: undefined },
      }),
    ).toBeNull();
  });
});

describe("botJobs", () => {
  it("enqueues a linked user's job with a ticket", async () => {
    const enqueue = vi.fn(async () => 7);
    const ticketFor = vi.fn(async (userId: string) => `ticket-${userId}`);
    const jobs = botJobs({ enqueue, ticketFor, principalByIdentity: linked });
    expect(await jobs.enqueue(author("U-alice"), { text: "hi" })).toEqual({
      result: 7,
      author: ALICE,
    });
    expect(ticketFor).toHaveBeenCalledWith("alice");
    expect(enqueue).toHaveBeenCalledWith(
      { text: "hi" },
      { ticket: "ticket-alice" },
    );
  });

  it("keeps an unlinked or contact author anonymous", async () => {
    const enqueue = vi.fn(() => 1);
    const ticketFor = vi.fn(() => "never");
    const jobs = botJobs({
      enqueue,
      ticketFor,
      server: server({ identities: { principalByIdentity: linked } }),
    });
    expect(await jobs.enqueue(author("U-stranger"), "a")).toEqual({
      result: 1,
      author: null,
    });
    expect(await jobs.enqueue(author("U-contact"), "b")).toEqual({
      result: 1,
      author: { kind: "contact", contactId: "contact-1" },
    });
    expect(enqueue.mock.calls).toEqual([
      ["a", {}],
      ["b", {}],
    ]);
    expect(ticketFor).not.toHaveBeenCalled();
    expect(
      await botJobs({ enqueue, ticketFor }).enqueue(author("U-alice"), "c"),
    ).toEqual({ result: 1, author: null });
  });

  it("enqueues nothing when resolving or issuing the ticket fails", async () => {
    const enqueue = vi.fn(() => 1);
    await expect(
      botJobs({
        enqueue,
        ticketFor: () => "t",
        principalByIdentity: () => Promise.reject(new Error("down")),
      }).enqueue(author("U-alice"), "a"),
    ).rejects.toThrow("down");
    await expect(
      botJobs({
        enqueue,
        ticketFor: () => "",
        principalByIdentity: linked,
      }).enqueue(author("U-alice"), "a"),
    ).rejects.toThrow("empty ticket");
    expect(enqueue).not.toHaveBeenCalled();
  });
});

describe("chatActions", () => {
  const approve = chatActionOf({
    actionId: "approve",
    value: "approval-1",
    user: { userId: "U-alice" },
    adapter: { name: "slack" },
  });

  it("builds the action from a Chat SDK event", () => {
    expect(approve).toEqual({
      id: "approve",
      value: "approval-1",
      author: author("U-alice"),
    });
    expect(
      chatActionOf(
        { actionId: "a", user: { userId: "U" }, adapter: { name: "teams" } },
        "W",
      ),
    ).toEqual({
      id: "a",
      author: { kind: "chat", provider: "teams", value: "U", workspace: "W" },
    });
  });

  it("allows what the hook allows for the linked author", async () => {
    const onAction = vi.fn<ChatActionHook>(() => ({ allowed: true }));
    const decide = chatActions({
      server: server({
        identities: { principalByIdentity: linked },
        chat: { onAction },
      }),
    });
    expect(await decide(approve)).toEqual({
      allowed: true,
      author: ALICE,
      userId: "alice",
    });
    expect(onAction).toHaveBeenCalledWith(approve, ALICE);
  });

  it("refuses an unlinked author before the hook runs", async () => {
    const onAction = vi.fn<ChatActionHook>(() => ({ allowed: true }));
    const decide = chatActions({ principalByIdentity: linked, onAction });
    expect(await decide({ ...approve, author: author("U-stranger") })).toEqual({
      allowed: false,
      reason: "unlinked",
    });
    expect(onAction).not.toHaveBeenCalled();
  });

  it.each<[string, ChatActionHook | undefined, string]>([
    ["no hook", undefined, "unhandled"],
    ["undefined", () => undefined, "unhandled"],
    ["allowed: false", () => ({ allowed: false }), "refused"],
    ["another user", () => ({ allowed: true, userId: "mallory" }), "refused"],
    [
      "a throw",
      () => {
        throw new Error("boom");
      },
      "error",
    ],
    ["a rejection", () => Promise.reject(new Error("boom")), "error"],
  ])("refuses %s", async (_name, onAction, reason) => {
    const decide = chatActions({
      principalByIdentity: linked,
      ...(onAction === undefined ? {} : { onAction }),
    });
    expect(await decide(approve)).toEqual({ allowed: false, reason });
  });

  it("refuses when the resolver throws", async () => {
    const decide = chatActions({
      principalByIdentity: () => {
        throw new Error("down");
      },
      onAction: () => ({ allowed: true }),
    });
    expect(await decide(approve)).toEqual({ allowed: false, reason: "error" });
  });

  it("lets the explicit hook win and keeps a contact's named user", async () => {
    const serverHook = vi.fn<ChatActionHook>(() => ({ allowed: false }));
    const decide = chatActions({
      principalByIdentity: linked,
      onAction: () => ({ allowed: true, userId: "staff-1" }),
      server: server({ chat: { onAction: serverHook } }),
    });
    const contact = { ...approve, author: author("U-contact") };
    expect(await decide(contact)).toEqual({
      allowed: true,
      author: { kind: "contact", contactId: "contact-1" },
      userId: "staff-1",
    });
    expect(serverHook).not.toHaveBeenCalled();
    expect(
      await chatActions({
        principalByIdentity: linked,
        onAction: () => ({ allowed: true }),
      })(contact),
    ).toEqual({
      allowed: true,
      author: { kind: "contact", contactId: "contact-1" },
    });
  });
});

describe("approval prompts", () => {
  const request = { kind: "tool", subject: "approval 1" };

  it("links to the approval page with the request", () => {
    expect(approvalLink("https://app.example.test/approvals", request)).toBe(
      "https://app.example.test/approvals?kind=tool&subject=approval+1",
    );
  });

  it("posts a markdown link that approves nothing by itself", () => {
    expect(
      approvalPrompt({
        page: new URL("https://app.example.test/a(b)"),
        request,
        text: "The agent wants to send an invoice.",
        label: "Open [request]",
      }),
    ).toEqual({
      markdown:
        "The agent wants to send an invoice.\n\n[Open \\[request\\]](https://app.example.test/a(b%29?kind=tool&subject=approval+1)",
    });
    expect(
      approvalPrompt({ page: "https://app.example.test/approvals", request })
        .markdown,
    ).toBe(
      "[Review the request](https://app.example.test/approvals?kind=tool&subject=approval+1)",
    );
  });
});
