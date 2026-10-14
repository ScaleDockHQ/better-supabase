import { describe, expect, it } from "vitest";

import type { AuthState } from "../../src/auth/resolve.ts";
import type {
  SupportApprover,
  SupportRequest,
  SupportSessionStore,
} from "../../src/auth/support.ts";
import type { BlockEvent } from "../../src/core/block-events.ts";
import type {
  ApprovalRequestRef,
  AuthorizationHooks,
} from "../../src/core/contracts/authorization-hooks.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { supportOff } from "../../src/server/support-off.ts";
import {
  type SupportOptions,
  supportSessions,
} from "../../src/server/support.ts";
import { pgError } from "../fixtures/fake-sql.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { memorySupportStore } from "../fixtures/support-store.ts";

const ADMIN = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const SECOND = "cccccccc-cccc-4ccc-8ccc-cccccccccccc";
const TARGET = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";

const user = (
  id: string,
  claims: Record<string, unknown> = {},
): Extract<AuthState, { kind: "user" }> => ({
  kind: "user",
  token: "t",
  claims: { sub: id, role: "authenticated", ...claims },
  user: { id, role: "authenticated" },
  source: "bearer",
  expiresAt: null,
});
const admin = user(ADMIN);
const second = user(SECOND);
const anon: AuthState = { kind: "anon", reason: "none" };

/** `memorySupportStore` with requests that refuse self-approval, as the SQL store does. */
function approvingStore() {
  const base = memorySupportStore();
  const requests = new Map<string, SupportRequest>();
  const approvers: SupportApprover[] = [];
  let next = 0;
  const selfApproval = () =>
    pgError("42501", "self", { hint: "SUPPORT_SELF_APPROVAL" });
  const store: SupportSessionStore = {
    ...base,
    request(input) {
      if (input.approvedBy === input.adminId)
        return Promise.reject(selfApproval());
      next += 1;
      const now = Temporal.Now.instant();
      const request: SupportRequest = {
        id: `r${String(next)}`,
        adminId: input.adminId,
        targetUserId: input.targetUserId,
        reason: input.reason,
        readOnly: input.readOnly,
        ...(input.tenant === undefined ? {} : { tenant: input.tenant }),
        metadata: input.metadata,
        requestedAt: now,
        expiresAt: now.add({ hours: 1 }),
        ...(input.approvedBy === undefined
          ? {}
          : { approvedBy: input.approvedBy, approvedAt: now }),
      };
      requests.set(request.id, request);
      return Promise.resolve(request);
    },
    getRequest: (id) => Promise.resolve(requests.get(id)),
    approve(id, approver) {
      approvers.push(approver);
      const found = requests.get(id);
      if (!found) return Promise.reject(new Error("missing"));
      if (found.adminId === approver.id) return Promise.reject(selfApproval());
      const approved = {
        ...found,
        approvedBy: approver.id,
        approvedAt: Temporal.Now.instant(),
      };
      requests.set(id, approved);
      return Promise.resolve(approved);
    },
    approvedRequest: (query) =>
      Promise.resolve(
        [...requests.values()].find(
          (request) =>
            request.adminId === query.adminId &&
            request.targetUserId === query.targetUserId &&
            request.tenant === query.tenant &&
            request.approvedBy !== undefined &&
            request.sessionId === undefined,
        ),
      ),
    async start(input) {
      const session = await base.start(input);
      const used = input.requestId && requests.get(input.requestId);
      if (used) requests.set(used.id, { ...used, sessionId: session.id });
      return session;
    },
  };
  return { store, requests, approvers };
}

function setup(
  options: Partial<SupportOptions> = {},
  hooks?: AuthorizationHooks,
) {
  const events: BlockEvent[] = [];
  const betterSupabase = defineSupabase(schema);
  betterSupabase.events.on("block", (event) => events.push(event));
  const approving = approvingStore();
  const support = supportSessions({
    store: approving.store,
    ...options,
  }).create(betterSupabase.events, undefined, undefined, hooks);
  return { support, events, ...approving };
}

const hooks = (patch: Partial<AuthorizationHooks>): AuthorizationHooks => ({
  apiVersion: 1,
  name: "test",
  ...patch,
});

const start = { targetUserId: TARGET, reason: "ticket 7" };

describe("support sessions refuse by default", () => {
  it("refuses a start without authorize or hooks", async () => {
    const { support, events } = setup();
    const result = await support.start(admin, start);
    expect(result.error).toMatchObject({
      kind: "forbidden",
      code: "SUPPORT_FORBIDDEN",
    });
    expect(events.at(-1)?.data).toMatchObject({ denial: "authorize" });
  });

  it("asks the hooks' support.authorize, and a slot passed directly wins", async () => {
    const asked: string[] = [];
    const fromHooks = hooks({
      support: {
        authorize: () => {
          asked.push("hooks");
          return false;
        },
      },
    });
    const viaHooks = setup({ policy: { approval: "none" } }, fromHooks);
    expect((await viaHooks.support.start(admin, start)).error?.code).toBe(
      "SUPPORT_FORBIDDEN",
    );
    const direct = setup(
      {
        policy: { approval: "none" },
        authorize: () => {
          asked.push("direct");
          return true;
        },
      },
      fromHooks,
    );
    expect((await direct.support.start(admin, start)).ok).toBe(true);
    expect(asked).toEqual(["hooks", "direct"]);
  });

  it("refuses an empty or blank reason before authorize runs", async () => {
    let asked = false;
    const { support } = setup({
      authorize: () => {
        asked = true;
        return true;
      },
    });
    for (const reason of ["", "   \n"]) {
      expect(
        (await support.start(admin, { targetUserId: TARGET, reason })).error
          ?.code,
      ).toBe("SUPPORT_REASON_REQUIRED");
    }
    expect(asked).toBe(false);
  });

  it("lets the store decide with authorize 'store', still behind a second admin", async () => {
    const { support } = setup({ authorize: "store" });
    expect((await support.start(admin, start)).error?.code).toBe(
      "SUPPORT_APPROVAL_REQUIRED",
    );
    const open = setup({ authorize: "store", policy: { approval: "none" } });
    expect((await open.support.start(admin, start)).ok).toBe(true);
  });
});

describe("support sessions need a second admin", () => {
  it("starts only after another admin approves the request, once", async () => {
    const { support, events, requests, approvers } = setup({
      authorize: () => true,
    });
    const refused = await support.start(admin, start);
    expect(refused.error).toMatchObject({
      kind: "forbidden",
      code: "SUPPORT_APPROVAL_REQUIRED",
    });
    expect(events.at(-1)?.data).toMatchObject({ denial: "policy" });

    const asked = await support.request(admin, start).orThrow();
    expect(asked).toMatchObject({ adminId: ADMIN, reason: "ticket 7" });
    expect((await support.approve(admin, asked.id)).error).toMatchObject({
      kind: "forbidden",
      code: "SUPPORT_SELF_APPROVAL",
    });
    expect((await support.start(admin, start)).error?.code).toBe(
      "SUPPORT_APPROVAL_REQUIRED",
    );

    const approved = await support.approve(second, asked.id).orThrow();
    expect(approved.approvedBy).toBe(SECOND);
    // Without approverOf the store decides, as the approver.
    expect(approvers).toEqual([{ id: SECOND, claims: second.claims }]);
    const started = await support.start(admin, start).orThrow();
    expect(requests.get(asked.id)?.sessionId).toBe(started.session.id);
    expect((await support.start(admin, start)).error?.code).toBe(
      "SUPPORT_APPROVAL_REQUIRED",
    );
  });

  it("takes an approvedBy decision for someone else, never the admin", async () => {
    const self = setup({ authorize: () => ({ approvedBy: ADMIN }) });
    const refused = await self.support.start(admin, start);
    expect(refused.error?.code).toBe("SUPPORT_SELF_APPROVAL");
    expect(self.events.at(-1)?.data).toMatchObject({ denial: "authorize" });

    const other = setup({ authorize: () => ({ approvedBy: SECOND }) });
    const { session } = await other.support.start(admin, start).orThrow();
    expect([...other.requests.values()]).toEqual([
      expect.objectContaining({
        adminId: ADMIN,
        approvedBy: SECOND,
        sessionId: session.id,
      }),
    ]);
  });

  it("asks approverOf, then records the approval for the server", async () => {
    const refs: ApprovalRequestRef[] = [];
    let answer: () => boolean = () => false;
    const { support, approvers } = setup(
      { authorize: () => true },
      hooks({
        approverOf: (approver, request) => {
          refs.push(request);
          expect(approver).toEqual({
            userId: SECOND,
            claims: second.claims,
          });
          return answer();
        },
      }),
    );
    const asked = await support
      .request(admin, { ...start, tenant: "o1" })
      .orThrow();
    expect((await support.approve(admin, asked.id)).error?.code).toBe(
      "SUPPORT_SELF_APPROVAL",
    );
    expect(refs).toEqual([]);
    expect((await support.approve(second, asked.id)).error?.code).toBe(
      "SUPPORT_FORBIDDEN",
    );
    answer = () => {
      throw new Error("down");
    };
    expect((await support.approve(second, asked.id)).error?.code).toBe(
      "SUPPORT_FORBIDDEN",
    );
    answer = () => true;
    await support.approve(second, asked.id).orThrow();
    expect(refs.at(-1)).toEqual({
      kind: "support-session",
      subject: asked.id,
      tenant: "o1",
      requester: ADMIN,
    });
    expect(approvers).toEqual([{ id: SECOND }]);
    expect((await support.start(admin, { ...start, tenant: "o1" })).ok).toBe(
      true,
    );
  });

  it("refuses approvals from anonymous, nested or unknown callers", async () => {
    const { support } = setup({ authorize: () => true });
    expect((await support.approve(anon, "r1")).error?.kind).toBe(
      "unauthorized",
    );
    expect(
      (await support.approve(user(SECOND, { act: { sub: "x" } }), "r1")).error
        ?.code,
    ).toBe("SUPPORT_NESTED");
    expect((await support.approve(second, "missing")).error).toMatchObject({
      kind: "not_found",
      code: "SUPPORT_REQUEST_MISSING",
    });
  });

  it("checks requests against the policy and maps store errors", async () => {
    const { support } = setup({ policy: { readOnly: "default" } });
    expect((await support.request(anon, start)).error?.kind).toBe(
      "unauthorized",
    );
    expect(
      (await support.request(admin, { targetUserId: TARGET, reason: " " }))
        .error?.code,
    ).toBe("SUPPORT_REASON_REQUIRED");
    expect(
      (await support.request(admin, { ...start, readOnly: false })).data,
    ).toMatchObject({ readOnly: false });

    const broken: SupportSessionStore = {
      ...approvingStore().store,
      request: () =>
        Promise.reject(pgError("42501", "no", { hint: "SUPPORT_FORBIDDEN" })),
      getRequest: () => Promise.reject(pgError("57014", "timeout")),
      approvedRequest: () => Promise.reject(pgError("42501", "no")),
    };
    const events: BlockEvent[] = [];
    const betterSupabase = defineSupabase(schema);
    betterSupabase.events.on("block", (event) => events.push(event));
    const brokenSupport = supportSessions({
      store: broken,
      authorize: () => true,
    }).create(betterSupabase.events, undefined);
    expect((await brokenSupport.request(admin, start)).error?.code).toBe(
      "42501",
    );
    expect((await brokenSupport.approve(second, "r1")).error?.kind).toBe(
      "timeout",
    );
    expect((await brokenSupport.start(admin, start)).error?.code).toBe("42501");
    expect(events.at(-1)?.data).toMatchObject({ denial: "permission" });
  });

  it("refuses starts that need an approval when the store records none", async () => {
    const events: BlockEvent[] = [];
    const betterSupabase = defineSupabase(schema);
    betterSupabase.events.on("block", (event) => events.push(event));
    const support = supportSessions({
      store: memorySupportStore(),
      authorize: () => ({ approvedBy: SECOND }),
    }).create(betterSupabase.events, undefined);
    expect((await support.start(admin, start)).error?.code).toBe(
      "SUPPORT_APPROVAL_REQUIRED",
    );
    const lookup = supportSessions({
      store: memorySupportStore(),
      authorize: () => true,
    }).create(betterSupabase.events, undefined);
    expect((await lookup.start(admin, start)).error?.code).toBe(
      "SUPPORT_APPROVAL_REQUIRED",
    );
    expect((await lookup.request(admin, start)).error).toMatchObject({
      kind: "unsupported",
      code: "SUPPORT_APPROVAL_UNSUPPORTED",
    });
    expect((await lookup.approve(second, "r1")).error?.code).toBe(
      "SUPPORT_APPROVAL_UNSUPPORTED",
    );
  });

  it("fails request and approve without support options", async () => {
    expect((await supportOff.request(admin, start)).ok).toBe(false);
    expect((await supportOff.approve(second, "r1")).ok).toBe(false);
  });
});
