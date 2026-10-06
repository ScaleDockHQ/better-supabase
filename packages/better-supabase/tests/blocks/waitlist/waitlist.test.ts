import { describe, expect, it, vi } from "vitest";

import type { BlockTransport } from "../../../src/blocks/waitlist/index.ts";

import {
  createWaitlist,
  generateInviteCode,
  waitlistHook,
} from "../../../src/blocks/waitlist/index.ts";
import { signWebhook } from "../../../src/blocks/webhooks/index.ts";

const entry = {
  id: "e1",
  email: "ada@example.com",
  status: "approved",
  position: 3,
  referrer: null,
  metadata: { source: "launch" },
  user_id: null,
  decided_by: "staff",
  decided_at: "2026-01-02T00:00:00Z",
  created_at: "2026-01-01T00:00:00Z",
};
const code = {
  id: "c1",
  prefix: "ABCD",
  max_uses: 5,
  uses: 1,
  expires_at: null,
  organization_id: "org",
  role: "admin",
  created_by: "u",
  created_at: "2026-01-01T00:00:00Z",
  revoked_at: null,
};

function fake(answer: (fn: string, args: Record<string, unknown>) => unknown) {
  const call = vi.fn(
    async (_schema: string, fn: string, args: Record<string, unknown>) =>
      answer(fn, args),
  );
  const transport: BlockTransport = { call };
  return { call, transport };
}

describe("createWaitlist", () => {
  it("joins and maps places", async () => {
    const { call, transport } = fake(() => ({
      position: 4,
      status: "waiting",
    }));
    const waitlist = createWaitlist({ transport, schema: "app" });
    expect(await waitlist.join("ada@example.com").orThrow()).toEqual({
      position: 4,
      status: "waiting",
    });
    expect(call).toHaveBeenCalledWith("app", "join_waitlist", {
      email: "ada@example.com",
      referrer: null,
      metadata: {},
    });
    await waitlist.join("b@example.com", {
      referrer: "ada",
      metadata: { utm: "x" },
    });
    expect(call.mock.calls[1]?.[2]).toMatchObject({
      referrer: "ada",
      metadata: { utm: "x" },
    });
  });

  it("reads rejected entries as waiting and rejects unknown statuses", async () => {
    let status = "rejected";
    const { transport } = fake(() => ({ position: null, status }));
    const waitlist = createWaitlist({ transport });
    expect(await waitlist.join("a@b.c").orThrow()).toEqual({
      position: undefined,
      status: "waiting",
    });
    status = "lost";
    const result = await waitlist.join("a@b.c");
    expect(result.ok).toBe(false);
  });

  it("lists, approves and rejects entries", async () => {
    const { call, transport } = fake((fn) =>
      fn === "list_waitlist" ? [entry] : entry,
    );
    const waitlist = createWaitlist({ transport });
    const [first] = await waitlist.entries().orThrow();
    expect(first).toMatchObject({
      id: "e1",
      status: "approved",
      position: 3,
      referrer: undefined,
      metadata: { source: "launch" },
      decidedBy: "staff",
    });
    expect(first?.decidedAt?.toString()).toBe("2026-01-02T00:00:00Z");
    expect(call.mock.calls[0]?.[2]).toEqual({
      status: "waiting",
      page_size: 50,
      after_position: null,
    });
    await waitlist.entries({ status: null, limit: 10, afterPosition: 3 });
    expect(call.mock.calls[1]?.[2]).toEqual({
      status: null,
      page_size: 10,
      after_position: 3,
    });
    await waitlist.approve("e1");
    await waitlist.reject("e1");
    expect(call.mock.calls.slice(2).map((c) => c[2])).toEqual([
      { id: "e1", approve: true },
      { id: "e1", approve: false },
    ]);
  });

  it("creates codes, returning the code once", async () => {
    const { call, transport } = fake((fn) =>
      fn === "list_invite_codes"
        ? [code]
        : fn === "revoke_invite_code"
          ? true
          : code,
    );
    const waitlist = createWaitlist({ transport });
    const created = await waitlist.createCode().orThrow();
    expect(created.code).toMatch(/^[A-HJ-NP-Z2-9]{4}(-[A-HJ-NP-Z2-9]{4}){3}$/);
    expect(created.invite).toMatchObject({
      prefix: "ABCD",
      maxUses: 5,
      organizationId: "org",
      role: "admin",
      expiresAt: undefined,
    });
    expect(call.mock.calls[0]?.[2]).toEqual({
      code: created.code,
      max_uses: 1,
      expires_at: undefined,
      tenant: null,
      role: null,
    });
    await waitlist.createCode({
      code: "LAUNCH2026",
      maxUses: null,
      expiresAt: Temporal.Instant.from("2026-02-01T00:00:00Z"),
      organizationId: "org",
      role: "admin",
    });
    expect(call.mock.calls[1]?.[2]).toMatchObject({
      code: "LAUNCH2026",
      max_uses: null,
      tenant: "org",
      role: "admin",
    });
    expect(await waitlist.codes("org").orThrow()).toHaveLength(1);
    expect(call.mock.calls[2]?.[2]).toEqual({ tenant: "org" });
    await waitlist.codes();
    expect(call.mock.calls[3]?.[2]).toEqual({ tenant: null });
    expect(await waitlist.revokeCode("c1").orThrow()).toBe(true);
  });

  it("redeems a code", async () => {
    const { transport } = fake(() => ({
      organizationId: "org",
      role: "member",
    }));
    const waitlist = createWaitlist({ transport });
    expect(await waitlist.redeem("ABCD").orThrow()).toEqual({
      organizationId: "org",
      role: "member",
    });
  });
});

describe("generateInviteCode", () => {
  it("draws from an alphabet without look-alike characters", () => {
    const codes = new Set(Array.from({ length: 50 }, generateInviteCode));
    expect(codes.size).toBe(50);
    for (const value of codes) expect(value).not.toMatch(/[01IO]/);
  });
});

describe("waitlistHook", () => {
  const secret = "v1,whsec_" + btoa("hook-secret-for-tests-0123456789");

  async function send(
    handler: (request: Request) => Promise<Response>,
    user: Record<string, unknown>,
  ) {
    const text = JSON.stringify({ metadata: {}, user });
    return handler(
      new Request("http://x/hook", {
        method: "POST",
        body: text,
        headers: await signWebhook(secret, { id: "msg_1", body: text }),
      }),
    );
  }

  it("admits approved addresses and valid codes", async () => {
    const { call, transport } = fake((_fn, args) => ({
      allowed: args["code"] === "GOOD" || args["email"] === "ok@x.test",
    }));
    const hook = waitlistHook({ transport, secret });
    const approved = await send(hook, { id: "u", email: "ok@x.test" });
    expect(approved.status).toBe(200);
    expect(await approved.json()).toEqual({});
    expect(call.mock.calls[0]?.[2]).toEqual({ email: "ok@x.test", code: null });

    const coded = await send(hook, {
      id: "u",
      email: "new@x.test",
      user_metadata: { invite_code: "GOOD" },
    });
    expect(coded.status).toBe(200);

    const rejected = await send(hook, {
      id: "u",
      email: "new@x.test",
      user_metadata: { invite_code: "" },
    });
    expect(rejected.status).toBe(403);
    expect(await rejected.json()).toEqual({
      error: {
        http_code: 403,
        message: "Sign-ups are invite-only. Join the waitlist first.",
      },
    });
  });

  it("reads another field, says its own message and fails closed", async () => {
    let fail = false;
    const { call, transport } = fake(() => {
      if (fail) throw Object.assign(new Error("down"), { code: "08006" });
      return { allowed: false };
    });
    const hook = waitlistHook({
      transport,
      secret,
      codeField: "referral",
      message: "Invite only",
    });
    const rejected = await send(hook, {
      id: "u",
      user_metadata: { referral: "X" },
    });
    expect(call.mock.calls[0]?.[2]).toEqual({ email: "", code: "X" });
    expect(await rejected.json()).toMatchObject({
      error: { message: "Invite only" },
    });
    fail = true;
    vi.spyOn(console, "error").mockImplementation(() => undefined);
    expect((await send(hook, { id: "u" })).status).toBe(500);
  });
});
