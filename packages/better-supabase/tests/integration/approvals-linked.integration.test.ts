import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const staff = { platform_permissions: ["support.*"] };
const REQUEST =
  "better_supabase.request_support_session($1, $2, true, '{}', $3)";
const APPROVE = "better_supabase.approve_support_request($1)";
const START =
  "better_supabase.start_support_session($1, $2, '30 minutes', true, '{}', $3)";
const DECIDE = "better_supabase.decide_approval($1, $2, $3)";

interface Approval {
  readonly id: string;
  readonly status: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly canDecide?: boolean;
}

describe.skipIf(!live)("requests other modules file in approvals", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  async function linked(s: BlockSession, subjectId: string): Promise<Approval> {
    await s.service();
    const [row] = await s.rows<{ id: string }>(
      "select id::text from better_supabase.approval_requests where subject_id = $1",
      [subjectId],
    );
    if (row === undefined) {
      throw new Error(`no approval for ${subjectId}`);
    }
    return s.value<Approval>("better_supabase.get_approval($1)", [row.id]);
  }

  it("decides a tool call from either side, and only its approver reads it", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "outbox", "ai-chat", "approvals"]);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const tenant = await s.organization(owner, { member });
      await s.as(owner);
      const chat = await s.value<{ id: string }>(
        "better_supabase.create_ai_chat($1)",
        [tenant],
      );
      await s.service();
      for (const id of ["ap1", "ap2", "ap3"]) {
        await s.value("better_supabase.record_ai_tool_approval($1, $2)", [
          chat.id,
          { approval_id: id, tool: "send_email", tool_call_id: `tc-${id}` },
        ]);
      }
      expect(await linked(s, "ap1")).toMatchObject({
        status: "pending",
        subjectType: "ai_tool_approval",
      });

      await s.asRole(member);
      expect(
        await s.rows("select 1 from better_supabase.approval_requests"),
      ).toHaveLength(0);
      expect(
        await s.value<unknown[]>("better_supabase.list_approvals($1)", [
          tenant,
        ]),
      ).toHaveLength(0);

      // Approving in the approvals block decides the tool call.
      const first = await linked(s, "ap1");
      await s.as(member);
      expect(await s.hint(DECIDE, [first.id, "approved", null])).toBe(
        "APPROVAL_FORBIDDEN",
      );
      await s.as(owner);
      expect(
        await s.value<unknown[]>(
          "better_supabase.list_approvals($1, 'pending', true)",
          [tenant],
        ),
      ).toHaveLength(3);
      expect(
        await s.value(DECIDE, [first.id, "approved", "fine"]),
      ).toMatchObject({ status: "approved" });
      expect(
        await s.value("better_supabase.get_ai_tool_approvals($1, $2)", [
          chat.id,
          ["ap1"],
        ]),
      ).toMatchObject([
        { decision: "approved", reason: "fine", decided_by: owner.id },
      ]);

      // Rejecting it there denies the tool call.
      const second = await linked(s, "ap2");
      await s.as(owner);
      await s.value(DECIDE, [second.id, "rejected", "no"]);
      expect(
        await s.value("better_supabase.get_ai_tool_approvals($1, $2)", [
          chat.id,
          ["ap2"],
        ]),
      ).toMatchObject([{ decision: "denied", reason: "no" }]);

      await s.as(owner, { act: { kind: "support" } });
      expect(
        await s.hint("better_supabase.decide_ai_tool_approval('ap3', true)"),
      ).toBe("ACTOR_READ_ONLY");

      // Deciding the tool call closes the request.
      await s.as(owner);
      await s.value("better_supabase.decide_ai_tool_approval('ap3', false)");
      expect(await linked(s, "ap3")).toMatchObject({
        status: "rejected",
        canDecide: false,
      });
    } finally {
      await s.close();
    }
  });

  it("decides a support request from either side", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "approvals", "support-sessions"]);
      const requester = await s.user("requester");
      const approver = await s.user("approver");
      const target = await s.user("target");
      const member = await s.user("member");
      const tenant = await s.organization(requester, { member });

      await s.as(requester, staff);
      const first = await s.value<{ id: string }>(REQUEST, [
        target.id,
        "ticket 1",
        tenant,
      ]);
      const request = await linked(s, first.id);
      expect(request).toMatchObject({
        status: "pending",
        subjectType: "support_request",
      });
      await s.as(requester, staff);
      expect(await s.hint(DECIDE, [request.id, "approved", null])).toBe(
        "APPROVAL_FORBIDDEN",
      );
      await s.as(member);
      expect(await s.hint(DECIDE, [request.id, "approved", null])).toBe(
        "APPROVAL_FORBIDDEN",
      );
      await s.asRole(member);
      expect(
        await s.rows("select 1 from better_supabase.approval_requests"),
      ).toHaveLength(0);

      // Approving in the approvals block lets the requester start.
      await s.as(approver, staff);
      expect(
        await s.value(DECIDE, [request.id, "approved", null]),
      ).toMatchObject({ status: "approved" });
      await s.as(requester, staff);
      expect(
        await s.value<{ id: string }>(START, [target.id, "ticket 1", tenant]),
      ).toHaveProperty("id");

      // Approving the support request closes the approval.
      const second = await s.value<{ id: string }>(REQUEST, [
        target.id,
        "ticket 2",
        tenant,
      ]);
      await s.as(approver, { ...staff, act: { kind: "support" } });
      expect(await s.hint(APPROVE, [second.id])).toBe("ACTOR_READ_ONLY");
      await s.as(approver, staff);
      await s.value(APPROVE, [second.id]);
      expect(await linked(s, second.id)).toMatchObject({ status: "approved" });

      // Rejecting it in the approvals block closes the support request.
      await s.as(requester, staff);
      const third = await s.value<{ id: string }>(REQUEST, [
        target.id,
        "ticket 3",
        tenant,
      ]);
      const rejected = await linked(s, third.id);
      await s.as(approver, staff);
      await s.value(DECIDE, [rejected.id, "rejected", "not now"]);
      expect(await s.hint(APPROVE, [third.id])).toBe("SUPPORT_REQUEST_CLOSED");

      // The support module decides who approves, so nobody delegates.
      await s.as(requester, staff);
      const fourth = await s.value<{ id: string }>(REQUEST, [
        target.id,
        "ticket 4",
        tenant,
      ]);
      const pending = await linked(s, fourth.id);
      await s.as(approver, staff);
      expect(
        await s.hint("better_supabase.delegate_approval($1, $2)", [
          pending.id,
          member.id,
        ]),
      ).toBe("APPROVAL_DELEGATE_INVALID");
    } finally {
      await s.close();
    }
  });
});
