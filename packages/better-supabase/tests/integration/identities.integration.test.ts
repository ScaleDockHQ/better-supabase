import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import {
  createIdentities,
  identityResolver,
  sqlTransport,
} from "../../src/blocks/identities/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();
const DENIED = /permission denied|Grant the required privileges/;

const slack = (value: string) =>
  ({ kind: "chat", provider: "slack", value, workspace: "T1" }) as const;

describe.skipIf(!live)("identities module", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("links a chat user through a code the signed-in user issued", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["identities"]);
      const alice = await s.user("alice");
      const bob = await s.user("bob");
      const identities = createIdentities({ transport: sqlTransport(s.sql) });
      const chatUser = `U${crypto.randomUUID().slice(0, 8)}`;

      await s.asRole(alice);

      const { code, expiresAt } = await identities
        .beginLink("chat", "slack")
        .orThrow();

      expect(code).toMatch(/^[0-9A-F]{12}$/);
      expect(expiresAt.epochMilliseconds).toBeGreaterThan(Date.now());

      await s.service();
      await s.client.query("set local role service_role");

      const linked = await identities
        .redeemLink(code.toLowerCase(), slack(chatUser))
        .orThrow();

      expect(linked.userId).toBe(alice.id);
      expect(
        await identityResolver(sqlTransport(s.sql))(slack(chatUser)),
      ).toEqual({ kind: "user", userId: alice.id });
      expect(
        await identityResolver(sqlTransport(s.sql))(slack("U-unlinked")),
      ).toBeNull();

      await s.asRole(alice);
      expect(
        (await identities.list().orThrow()).filter((i) => i.kind === "chat"),
      ).toMatchObject([
        { value: chatUser, provider: "slack", workspace: "T1", source: "link" },
      ]);

      await s.asRole(bob);
      expect(
        await s.rows(
          "select id from better_supabase.identity_links where value = $1",
          [chatUser],
        ),
      ).toEqual([]);
      expect(await identities.unlink(linked.id).orThrow()).toBe(false);

      await s.asRole(alice);
      expect(await identities.unlink(linked.id).orThrow()).toBe(true);
    } finally {
      await s.close();
    }
  });

  it("refuses direct writes, anon reads and user calls to the service functions", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["identities"]);
      const alice = await s.user("alice");
      const bob = await s.user("bob");

      await s.asRole(bob);
      expect(
        await s.hint(
          "insert into better_supabase.identity_links (kind, provider, value, user_id, source) values ('chat', 'slack', 'U1', $1, 'link')",
          [alice.id],
        ),
      ).toMatch(DENIED);
      expect(
        await s.hint("update better_supabase.identity_links set user_id = $1", [
          bob.id,
        ]),
      ).toMatch(DENIED);
      expect(
        await s.hint("select * from better_supabase.identity_link_codes"),
      ).toMatch(DENIED);
      expect(
        await s.hint(
          "better_supabase.redeem_identity_link('X', 'chat', 'slack', 'U1')",
        ),
      ).toMatch(DENIED);
      expect(
        await s.hint(
          "better_supabase.principal_by_identity('chat', 'slack', 'U1')",
        ),
      ).toMatch(DENIED);

      await s.asRole("anon");
      expect(
        await s.hint("select * from better_supabase.identity_links"),
      ).toMatch(DENIED);
      expect(
        await s.hint("better_supabase.begin_identity_link('chat', 'slack')"),
      ).toMatch(DENIED);

      await s.as("anon");
      expect(
        await s.hint("better_supabase.begin_identity_link('chat', 'slack')"),
      ).toBe("IDENTITY_SIGN_IN_REQUIRED");
      await s.as(alice);
      expect(
        await s.hint("better_supabase.begin_identity_link('fax', null)"),
      ).toBe("IDENTITY_KIND");
    } finally {
      await s.close();
    }
  });

  it("refuses a reused, expired, replaced or mismatched code and a taken identity", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["identities"]);
      const alice = await s.user("alice");
      const bob = await s.user("bob");
      const identities = createIdentities({ transport: sqlTransport(s.sql) });

      const begin = async (user: typeof alice): Promise<string> => {
        await s.as(user);
        const { code } = await identities.beginLink("chat", "slack").orThrow();
        await s.service();

        return code;
      };

      const redeem = (code: string, value: string) =>
        identities.redeemLink(code, slack(value));

      const once = await begin(alice);
      await redeem(once, "U-alice").orThrow();
      expect(await redeem(once, "U-alice-2")).toMatchObject({
        ok: false,
        error: { hint: "IDENTITY_LINK_INVALID" },
      });

      const expired = await begin(alice);
      await s.client.query(
        "update better_supabase.identity_link_codes set expires_at = now() - interval '1 second' where user_id = $1 and used_at is null",
        [alice.id],
      );
      expect(await redeem(expired, "U-alice-3")).toMatchObject({
        ok: false,
        error: { hint: "IDENTITY_LINK_INVALID" },
      });

      const replaced = await begin(alice);
      await begin(alice);
      expect(await redeem(replaced, "U-alice-4")).toMatchObject({
        ok: false,
        error: { hint: "IDENTITY_LINK_INVALID" },
      });

      const wrongProvider = await begin(alice);
      expect(
        await identities.redeemLink(wrongProvider, {
          kind: "chat",
          provider: "teams",
          value: "U-alice-5",
        }),
      ).toMatchObject({ ok: false, error: { hint: "IDENTITY_LINK_INVALID" } });

      expect(await redeem(await begin(bob), "U-alice")).toMatchObject({
        ok: false,
        error: { hint: "IDENTITY_TAKEN" },
      });
      const again = await begin(alice);
      expect((await redeem(again, "U-alice").orThrow()).userId).toBe(alice.id);
    } finally {
      await s.close();
    }
  });

  it("creates email identities from confirmed addresses only", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["identities"]);
      const confirmed = await s.user("confirmed");
      const id = crypto.randomUUID();
      const pending = `Pending-${id.slice(0, 8)}@example.test`;
      await s.client.query(
        `insert into auth.users (id, email, aud, role, instance_id)
         values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000')`,
        [id, pending],
      );
      const resolve = identityResolver(sqlTransport(s.sql));

      await s.service();
      expect(await resolve({ kind: "email", value: confirmed.email })).toEqual({
        kind: "user",
        userId: confirmed.id,
      });
      expect(
        await resolve({
          kind: "email",
          provider: "postmark",
          value: confirmed.email.toUpperCase(),
        }),
      ).toEqual({ kind: "user", userId: confirmed.id });
      expect(await resolve({ kind: "email", value: pending })).toBeNull();
      expect(
        await s.value("better_supabase.link_verified_email($1)", [id]),
      ).toBe(false);

      await s.client.query(
        "update auth.users set email_confirmed_at = now() where id = $1",
        [id],
      );
      expect(
        await resolve({ kind: "email", value: pending.toLowerCase() }),
      ).toEqual({ kind: "user", userId: id });

      const moved = `moved-${id.slice(0, 8)}@example.test`;
      await s.client.query("update auth.users set email = $2 where id = $1", [
        id,
        moved,
      ]);
      expect(await resolve({ kind: "email", value: pending })).toBeNull();
      expect(await resolve({ kind: "email", value: moved })).toEqual({
        kind: "user",
        userId: id,
      });
      const identities = createIdentities({ transport: sqlTransport(s.sql) });
      await identities.backfillVerifiedEmails().orThrow();
      expect(await identities.backfillVerifiedEmails().orThrow()).toBe(0);
    } finally {
      await s.close();
    }
  });
});
