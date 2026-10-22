import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../src/sql/module-types.ts";
import type { TestUser } from "./block-session.ts";

import { renderBlocks } from "../../src/sql/render.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const staff = { platform_permissions: ["support.*"] };
const START = "better_supabase.start_support_session($1, $2)";
const REQUEST = "better_supabase.request_support_session($1, $2)";
const APPROVE = "better_supabase.approve_support_request($1)";

interface Request {
  readonly id: string;
  readonly admin_id: string;
  readonly approved_by: string | null;
  readonly session_id: string | null;
}

/**
 * Installs `module` from `layout` over what the session already has, its own
 * file only.
 */
async function reinstall(
  s: BlockSession,
  modules: readonly string[],
  module: string,
  layout: BlockSqlLayout,
): Promise<void> {
  await s.client.query("reset role");

  for (const file of renderBlocks(modules, layout)) {
    if (file.module === module && file.kind === "schema") {
      await s.client.query(file.contents);
    }
  }
}

/**
 * A provider whose `isApprover` allows everyone for `kind`, so only the
 * requester check can refuse.
 */
async function providerLayout(
  s: BlockSession,
  kind: string,
): Promise<BlockSqlLayout> {
  const schema = `approver_${crypto.randomUUID().slice(0, 8)}`;
  await s.client.query(`
    create schema ${schema};
    create function ${schema}.is_approver(kind text, subject text, tenant uuid) returns boolean
      language sql stable as $$ select kind = '${kind}' and subject is not null $$;
    grant usage on schema ${schema} to authenticated;
  `);

  return {
    modules: { access: { model: "provider" } },
    accessProvider: {
      name: "test",
      scope: "organization",
      idType: "uuid",
      functions: {
        idsWith: "better_supabase.tenant_ids_with({permission})",
        isPlatform: "better_supabase.is_platform({permission})",
        isApprover: `${schema}.is_approver({kind}, {subject}, {tenant})`,
      },
    },
  };
}

describe.skipIf(!live)("support session approvals as real users", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  async function setUp(s: BlockSession) {
    await s.install(["support-sessions"]);
    const requester = await s.user("requester");
    const approver = await s.user("approver");
    const outsider = await s.user("outsider");
    const target = await s.user("target");

    return { requester, approver, outsider, target };
  }

  it("starts only after a different eligible admin approves, once", async () => {
    const s = await BlockSession.open(pool);

    try {
      const { requester, approver, outsider, target } = await setUp(s);
      const third = await s.user("third");
      await s.asRole(requester, staff);
      expect(await s.hint(START, [target.id, "ticket 1"])).toBe(
        "SUPPORT_APPROVAL_REQUIRED",
      );

      for (const reason of [null, "", "   "]) {
        expect(await s.hint(START, [target.id, reason])).toBe(
          "SUPPORT_REASON_REQUIRED",
        );
        expect(await s.hint(REQUEST, [target.id, reason])).toBe(
          "SUPPORT_REASON_REQUIRED",
        );
      }

      const request = await s.value<Request>(REQUEST, [target.id, "ticket 1"]);
      expect(request).toMatchObject({
        admin_id: requester.id,
        approved_by: null,
      });
      expect(await s.hint(APPROVE, [request.id])).toBe("SUPPORT_SELF_APPROVAL");
      expect(await s.hint(START, [target.id, "ticket 1"])).toBe(
        "SUPPORT_APPROVAL_REQUIRED",
      );

      await s.asRole(outsider);
      expect(await s.hint(APPROVE, [request.id])).toBe("SUPPORT_FORBIDDEN");

      await s.asRole(approver, staff);
      expect(await s.value<Request>(APPROVE, [request.id])).toMatchObject({
        approved_by: approver.id,
      });
      expect(await s.value<Request>(APPROVE, [request.id])).toMatchObject({
        approved_by: approver.id,
      });

      await s.asRole(requester, staff);

      const session = await s.value<{ id: string }>(START, [
        target.id,
        "ticket 1",
      ]);

      const [used] = await s.rows<Request>(
        "select session_id::text from better_supabase.support_requests where id = $1",
        [request.id],
      );

      expect(used?.session_id).toBe(session.id);
      expect(await s.hint(START, [target.id, "ticket 1"])).toBe(
        "SUPPORT_APPROVAL_REQUIRED",
      );
      await s.asRole(third, staff);
      expect(await s.hint(APPROVE, [request.id])).toBe(
        "SUPPORT_REQUEST_DECIDED",
      );
    } finally {
      await s.close();
    }
  });

  it("gives a client no way around the second admin", async () => {
    const s = await BlockSession.open(pool);

    try {
      const { requester, approver, target } = await setUp(s);
      await s.asRole(requester, staff);

      const forged =
        "better_supabase.request_support_session($1, $2, true, '{}', null, null, $3)";

      expect(await s.hint(forged, [target.id, "ticket", approver.id])).toBe(
        "SUPPORT_FORBIDDEN",
      );
      expect(await s.hint(forged, [target.id, "ticket", requester.id])).toBe(
        "SUPPORT_FORBIDDEN",
      );
      expect(
        await s.hint("better_supabase.approve_support_request($1, $2)", [
          crypto.randomUUID(),
          approver.id,
        ]),
      ).toBe("SUPPORT_FORBIDDEN");

      const request = await s.value<Request>(REQUEST, [target.id, "ticket"]);
      expect(
        await s.hint(
          "update better_supabase.support_requests set approved_by = $1, approved_at = now() where id = $2",
          [approver.id, request.id],
        ),
      ).toMatch(/GRANT UPDATE ON better_supabase.support_requests/);
      expect(
        await s.hint(
          "insert into better_supabase.support_requests (admin_id, target_user_id, reason, expires_at, approved_by, approved_at) values ($1, $2, 'x', now() + interval '1 hour', $3, now())",
          [requester.id, target.id, approver.id],
        ),
      ).toMatch(/GRANT INSERT ON better_supabase.support_requests/);
      expect(
        await s.rows("select id from better_supabase.support_requests"),
      ).toHaveLength(1);
      await s.asRole(approver);
      expect(
        await s.rows("select id from better_supabase.support_requests"),
      ).toHaveLength(0);

      // Even the service role and the table owner can't record a self-approval.
      await s.service();
      expect(
        await s.hint(
          "better_supabase.request_support_session($1, $2, true, '{}', null, $3, $3)",
          [target.id, "ticket", requester.id],
        ),
      ).toBe("SUPPORT_SELF_APPROVAL");
      expect(
        await s.hint(
          "update better_supabase.support_requests set approved_by = admin_id, approved_at = now() where id = $1",
          [request.id],
        ),
      ).toMatch(/support_requests_distinct_approver/);

      // The server records an approval its authorization hook decided.
      await s.value(
        "better_supabase.request_support_session($1, $2, true, '{}', null, $3, $4)",
        [target.id, "ticket 2", requester.id, approver.id],
      );
      await s.asRole(requester, staff);
      expect(
        await s.value<{ admin_id: string }>(START, [target.id, "ticket 2"]),
      ).toMatchObject({ admin_id: requester.id });
    } finally {
      await s.close();
    }
  });

  it("asks the provider's isApprover and still refuses the requester", async () => {
    const s = await BlockSession.open(pool);

    try {
      const { requester, outsider, target } = await setUp(s);
      const layout = await providerLayout(s, "support-session");
      await reinstall(s, ["support-sessions"], "support-sessions", layout);
      await s.asRole(requester, staff);
      const request = await s.value<Request>(REQUEST, [target.id, "ticket"]);
      expect(await s.hint(APPROVE, [request.id])).toBe("SUPPORT_SELF_APPROVAL");
      // The outsider holds no platform permission; isApprover alone decides.
      await s.asRole(outsider);
      expect(await s.value<Request>(APPROVE, [request.id])).toMatchObject({
        approved_by: outsider.id,
      });
    } finally {
      await s.close();
    }
  });
});

describe.skipIf(!live)("ai-chat tool approvals through isApprover", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("never lets the chat's owner approve their own tool call", async () => {
    const s = await BlockSession.open(pool);

    try {
      const modules = ["organizations", "outbox", "ai-chat"];
      await s.install(modules);
      const owner: TestUser = await s.user("owner");
      const member: TestUser = await s.user("member");
      const tenant = await s.organization(owner, { member });
      await reinstall(
        s,
        modules,
        "ai-chat",
        await providerLayout(s, "ai-tool"),
      );
      await s.as(owner);

      const chat = await s.value<{ id: string }>(
        "better_supabase.create_ai_chat($1)",
        [tenant],
      );

      await s.service();
      await s.value("better_supabase.record_ai_tool_approval($1, $2)", [
        chat.id,
        { approval_id: "ap1", tool: "send_email", tool_call_id: "tc1" },
      ]);
      await s.asRole(owner);
      expect(
        await s.hint("better_supabase.decide_ai_tool_approval('ap1', true)"),
      ).toBe("AI_APPROVAL_NOT_FOUND");
      await s.asRole(member);
      expect(
        await s.value("better_supabase.decide_ai_tool_approval('ap1', true)"),
      ).toMatchObject({ decision: "approved", decided_by: member.id });
    } finally {
      await s.close();
    }
  });
});
