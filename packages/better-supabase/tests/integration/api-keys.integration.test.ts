import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import {
  createApiKeys,
  parseApiKey,
  sqlTransport,
} from "../../src/blocks/api-keys/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)("api-keys", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("creates, verifies, rate-limits, rotates and revokes keys", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "api-keys"]);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const outsider = await s.user("outsider");
      const organization = await s.organization(owner, { member });
      const keys = createApiKeys({ transport: sqlTransport(s.sql) });

      // A member can't create a tenant key, but can create a personal one.
      await s.as(member);
      const denied = await keys.create({
        name: "CI",
        organizationId: organization,
      });
      expect(denied).toMatchObject({
        ok: false,
        error: { kind: "forbidden", hint: "API_KEY_FORBIDDEN" },
      });
      const personal = await keys
        .create({
          name: "Mine",
          organizationId: organization,
          personal: true,
          scopes: ["deals:read"],
        })
        .orThrow();
      expect(personal.key).toMatchObject({
        userId: member.id,
        organizationId: organization,
      });

      await s.as(outsider);
      expect(
        await keys.create({
          name: "X",
          organizationId: organization,
          personal: true,
        }),
      ).toMatchObject({ ok: false, error: { hint: "API_KEY_FORBIDDEN" } });

      await s.as(owner);
      const ci = await keys
        .create({
          name: "CI",
          organizationId: organization,
          scopes: ["*"],
          rateLimit: 2,
        })
        .orThrow();
      expect(parseApiKey(ci.token)?.publicId).toBe(ci.key.publicId);
      expect(
        await s.value<string>(
          "(select secret_hash from better_supabase.api_keys where id = $1)",
          [ci.key.id],
        ),
      ).not.toContain(parseApiKey(ci.token)!.secret);
      // Managers see the tenant's keys; members only their own.
      expect(
        (await keys.list(organization).orThrow()).map((k) => k.name).sort(),
      ).toEqual(["CI", "Mine"]);
      await s.as(member);
      expect(
        (await keys.list(organization).orThrow()).map((k) => k.name),
      ).toEqual(["Mine"]);
      expect(await keys.revoke(ci.key.id)).toMatchObject({
        ok: false,
        error: { hint: "API_KEY_NOT_FOUND" },
      });

      // Verification runs as the service role and counts requests.
      await s.service();
      expect(await keys.verify(ci.token).orThrow()).toMatchObject({
        status: "ok",
        key: { id: ci.key.id, scopes: ["*"] },
      });
      await keys.verify(ci.token).orThrow();
      expect(await keys.verify(ci.token).orThrow()).toMatchObject({
        status: "rate_limited",
      });
      const tampered = `${ci.token.slice(0, -1)}${ci.token.endsWith("x") ? "y" : "x"}`;
      expect(await keys.verify(tampered).orThrow()).toEqual({
        status: "invalid",
      });
      expect(
        await s.value(
          "(select last_used_at is not null from better_supabase.api_keys where id = $1)",
          [ci.key.id],
        ),
      ).toBe(true);
      await s.asRole(owner);
      expect(
        await s.hint(
          "select better_supabase.verify_api_key('0123456789abcdef', $1)",
          ["0".repeat(64)],
        ),
      ).toMatch(/permission denied/);

      // Rotation keeps the old key valid for the grace period.
      const rotated = await keys
        .rotate(personal.key.id, {
          grace: Temporal.Duration.from({ hours: 1 }),
        })
        .orThrow();
      expect(rotated.key.rotatedFrom).toBe(personal.key.id);
      expect(rotated.key.state).toBe("active");
      const during = await keys.list(organization).orThrow();
      expect(during.find((k) => k.id === personal.key.id)).toMatchObject({
        state: "grace",
        successorId: rotated.key.id,
      });
      await s.service();
      expect(await keys.verify(personal.token).orThrow()).toMatchObject({
        status: "ok",
      });
      expect(await keys.verify(rotated.token).orThrow()).toMatchObject({
        status: "ok",
      });
      await s.client.query(
        "update auth.users set banned_until = now() + interval '1 day' where id = $1",
        [member.id],
      );
      expect(await keys.verify(rotated.token).orThrow()).toEqual({
        status: "invalid",
      });
      await s.client.query(
        "update auth.users set banned_until = now() - interval '1 minute' where id = $1",
        [member.id],
      );
      expect(await keys.verify(rotated.token).orThrow()).toMatchObject({
        status: "ok",
      });
      await s.as(owner);
      expect(await keys.revoke(personal.key.id).orThrow()).toBe(true);
      expect(
        (await keys.list(organization).orThrow()).find(
          (k) => k.id === personal.key.id,
        )?.state,
      ).toBe("revoked");
      await s.service();
      expect(await keys.verify(personal.token).orThrow()).toEqual({
        status: "invalid",
      });

      // A personal key stops working once its user leaves the tenant.
      await s.client.query(
        "delete from better_supabase.memberships where user_id = $1",
        [member.id],
      );
      expect(await keys.verify(rotated.token).orThrow()).toEqual({
        status: "invalid",
      });

      // has_scope and api_key_tenant read the synthesized claims.
      await s.as(owner, {
        api_key: {
          id: ci.key.id,
          organization_id: organization,
          scopes: ["deals:read"],
        },
      });
      expect(await s.value("better_supabase.has_scope('deals:read')")).toBe(
        true,
      );
      expect(await s.value("better_supabase.has_scope('deals:write')")).toBe(
        false,
      );
      expect(await s.value("better_supabase.api_key_tenant()")).toBe(
        organization,
      );
      await s.as(owner);
      expect(await s.value("better_supabase.has_scope('anything')")).toBe(true);
      expect(await s.value("better_supabase.api_key_tenant()")).toBeNull();
    } finally {
      await s.close();
    }
  });
  it("needs the own permission in every tenant for a key without a tenant", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "api-keys"]);
      const owner = await s.user("owner");
      const both = await s.user("both");
      const member = await s.user("member");
      const outsider = await s.user("outsider");
      await s.organization(owner, { viewer: both });
      await s.organization(owner, { member: both, member2: member });
      const keys = createApiKeys({ transport: sqlTransport(s.sql) });

      await s.as(both);
      expect(await keys.create({ name: "All", personal: true })).toMatchObject({
        ok: false,
        error: { kind: "forbidden", hint: "API_KEY_FORBIDDEN" },
      });

      await s.as(member);
      expect(
        (await keys.create({ name: "All", personal: true }).orThrow()).key,
      ).toMatchObject({ userId: member.id });

      await s.as(outsider);
      expect(
        (await keys.create({ name: "Own", personal: true }).orThrow()).key,
      ).toMatchObject({ userId: outsider.id });
    } finally {
      await s.close();
    }
  });
});
