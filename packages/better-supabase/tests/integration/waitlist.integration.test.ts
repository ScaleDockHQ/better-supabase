import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import {
  createWaitlist,
  sqlTransport,
} from "../../src/blocks/waitlist/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const signUp = (s: BlockSession, email: string, metadata: object = {}) => {
  const id = crypto.randomUUID();
  return s
    .rows(
      `insert into auth.users (id, email, aud, role, instance_id, raw_user_meta_data)
       values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', $3)`,
      [id, email, metadata],
    )
    .then(() => id);
};

const admit = (s: BlockSession, email: string, code: string | null = null) =>
  s.value<{ allowed: boolean; reason: string }>(
    "better_supabase.waitlist_admit($1, $2)",
    [email, code],
  );

describe.skipIf(!live)("waitlist", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("queues, approves and admits addresses", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "outbox", "waitlist"]);
      const tag = crypto.randomUUID().slice(0, 8);
      const first = `first-${tag}@example.test`;
      const second = `second-${tag}@example.test`;
      const owner = await s.user("owner");

      await s.as("anon");
      const waitlist = createWaitlist({ transport: sqlTransport(s.sql) });
      const place = await waitlist.join(` ${first.toUpperCase()} `).orThrow();
      const next = await waitlist
        .join(second, { referrer: "friend", metadata: { plan: "team" } })
        .orThrow();
      expect(next.position).toBe((place.position ?? 0) + 1);
      expect(await waitlist.join(first).orThrow()).toEqual(place);
      expect(
        await waitlist.join("nope").then((r) => !r.ok && r.error.hint),
      ).toBe("WAITLIST_EMAIL_INVALID");
      expect(await waitlist.entries().then((r) => !r.ok && r.error.hint)).toBe(
        "WAITLIST_FORBIDDEN",
      );

      await s.service();
      expect(await admit(s, first)).toEqual({
        allowed: false,
        reason: "waiting",
      });
      const entries = await waitlist
        .entries({ afterPosition: 0, limit: 500 })
        .orThrow();
      const entry = entries.find((e) => e.email === second);
      expect(entry).toMatchObject({
        referrer: "friend",
        metadata: { plan: "team" },
      });
      const firstEntry = entries.find((e) => e.email === first)!;
      const approved = await waitlist.approve(firstEntry.id).orThrow();
      expect(approved.status).toBe("approved");
      await waitlist.reject(entry!.id).orThrow();
      expect(await admit(s, first.toUpperCase())).toEqual({
        allowed: true,
        reason: "approved",
      });
      expect(await admit(s, second)).toMatchObject({ allowed: false });
      await s.as("anon");
      expect((await waitlist.join(second).orThrow()).status).toBe("waiting");
      await s.service();
      expect(
        await s.rows(
          "select type from better_supabase.outbox_events where type = 'waitlist.approved' and payload ->> 'entryId' = $1",
          [firstEntry.id],
        ),
      ).toHaveLength(1);

      const userId = await signUp(s, first);
      expect(
        await s.value(
          "(select status from better_supabase.waitlist_entries where id = $1)",
          [firstEntry.id],
        ),
      ).toBe("joined");
      expect(
        await waitlist
          .approve(firstEntry.id)
          .then((r) => !r.ok && r.error.hint),
      ).toBe("WAITLIST_NOT_FOUND");
      expect(
        await s.value(
          "(select user_id from better_supabase.waitlist_entries where id = $1)",
          [firstEntry.id],
        ),
      ).toBe(userId);
      expect(await admit(s, first)).toMatchObject({ allowed: true });

      await s.as(owner);
      expect(
        await waitlist
          .approve(firstEntry.id)
          .then((r) => !r.ok && r.error.hint),
      ).toBe("WAITLIST_FORBIDDEN");
    } finally {
      await s.close();
    }
  });

  it("creates, redeems and limits invite codes", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "outbox", "waitlist"]);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const tenant = await s.organization(owner, { member });
      const waitlist = createWaitlist({ transport: sqlTransport(s.sql) });

      await s.as(member);
      expect(
        await waitlist
          .createCode({ organizationId: tenant })
          .then((r) => !r.ok && r.error.hint),
      ).toBe("WAITLIST_FORBIDDEN");
      await s.as(owner);
      expect(
        await waitlist.createCode().then((r) => !r.ok && r.error.hint),
      ).toBe("WAITLIST_FORBIDDEN");
      expect(
        await waitlist
          .createCode({ organizationId: tenant, role: "owner" })
          .then((r) => !r.ok && r.error.hint),
      ).toBe("WAITLIST_ROLE_INVALID");
      expect(
        await waitlist
          .createCode({ organizationId: tenant, code: "short" })
          .then((r) => !r.ok && r.error.hint),
      ).toBe("WAITLIST_CODE_INVALID");
      const { code, invite } = await waitlist
        .createCode({ organizationId: tenant, role: "admin", maxUses: 2 })
        .orThrow();
      expect(invite).toMatchObject({
        prefix: code.slice(0, 4),
        uses: 0,
        maxUses: 2,
      });
      expect(
        await waitlist
          .createCode({ organizationId: tenant, code: code.toLowerCase() })
          .then((r) => !r.ok && r.error.hint),
      ).toBe("WAITLIST_CODE_TAKEN");
      expect((await waitlist.codes(tenant).orThrow()).map((c) => c.id)).toEqual(
        [invite.id],
      );
      expect(
        JSON.stringify(
          await s.value("better_supabase.list_invite_codes($1)", [tenant]),
        ),
      ).not.toContain(code);

      await s.service();
      expect(await admit(s, "new@example.test", code.toLowerCase())).toEqual({
        allowed: true,
        reason: "code",
      });
      expect(await admit(s, "new@example.test", "WRONG-CODE")).toEqual({
        allowed: false,
        reason: "code_invalid",
      });

      const joined = await signUp(
        s,
        `joined-${crypto.randomUUID().slice(0, 8)}@example.test`,
        {
          invite_code: code,
          name: "Ada",
        },
      );
      expect(
        await s.value(
          "(select role from better_supabase.memberships where organization_id = $1 and user_id = $2)",
          [tenant, joined],
        ),
      ).toBe("admin");
      expect(
        await s.value(
          "(select raw_user_meta_data from auth.users where id = $1)",
          [joined],
        ),
      ).toEqual({ name: "Ada" });
      expect(
        await s.rows(
          "select type from better_supabase.outbox_events where organization_id = $1 and type = 'organization.member_added'",
          [tenant],
        ),
      ).toHaveLength(1);

      await s.as({ id: joined, email: "" });
      expect(
        await waitlist.redeem(code).then((r) => !r.ok && r.error.hint),
      ).toBe("WAITLIST_CODE_USED");
      await s.as(member);
      expect(await waitlist.redeem(code).orThrow()).toEqual({
        organizationId: tenant,
        role: undefined,
      });
      expect(
        await s.value(
          "(select role from better_supabase.memberships where organization_id = $1 and user_id = $2)",
          [tenant, member.id],
        ),
      ).toBe("member");
      const late = await s.user("late");
      await s.as(late);
      expect(
        await waitlist.redeem(code).then((r) => !r.ok && r.error.hint),
      ).toBe("WAITLIST_CODE_INVALID");
      await s.as(owner);
      const viewerCode = await waitlist
        .createCode({ organizationId: tenant, role: "viewer" })
        .orThrow();
      await s.as(late);
      expect(await waitlist.redeem(viewerCode.code).orThrow()).toEqual({
        organizationId: tenant,
        role: "viewer",
      });

      await s.service();
      const failed = await signUp(
        s,
        `bad-${crypto.randomUUID().slice(0, 8)}@example.test`,
        {
          invite_code: code,
        },
      );
      expect(
        await s.value(
          "(select raw_user_meta_data from auth.users where id = $1)",
          [failed],
        ),
      ).toEqual({});

      await s.as(owner);
      expect(await waitlist.revokeCode(invite.id).orThrow()).toBe(true);
      expect(await waitlist.revokeCode(invite.id).orThrow()).toBe(false);
      expect(await waitlist.revokeCode(crypto.randomUUID()).orThrow()).toBe(
        false,
      );
      await s.service();
      const platform = await waitlist.createCode({ maxUses: null }).orThrow();
      expect((await waitlist.codes().orThrow()).map((c) => c.id)).toContain(
        platform.invite.id,
      );
      await s.as(owner);
      expect(
        await waitlist
          .revokeCode(platform.invite.id)
          .then((r) => !r.ok && r.error.hint),
      ).toBe("WAITLIST_FORBIDDEN");
      await s.as("anon");
      expect(
        await waitlist.redeem(platform.code).then((r) => !r.ok && r.error.hint),
      ).toBe("WAITLIST_FORBIDDEN");
    } finally {
      await s.close();
    }
  });
});
