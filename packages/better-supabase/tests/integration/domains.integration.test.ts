import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import {
  createDomains,
  createDomainsAdmin,
  sqlTransport,
} from "../../src/blocks/domains/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const host = (prefix = "app") =>
  `${prefix}.acme-${crypto.randomUUID().slice(0, 8)}.test`;

const PLATFORM = "platform-domains.test";

interface Row {
  id: string;
  hostname: string;
  kind: string;
  verified_at: string | null;
  record?: { name: string; value: string };
  verification_token?: string;
}

describe.skipIf(!live)("domains module", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("verifies a custom domain for one organization and resolves it", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "outbox", "domains"]);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const rival = await s.user("rival");
      const tenant = await s.organization(owner, { member });
      const other = await s.organization(rival);
      const name = host();

      await s.as(owner);

      const added = await s.value<Row>("better_supabase.add_hostname($1, $2)", [
        tenant,
        ` ${name.toUpperCase()}. `,
      ]);

      expect(added).toMatchObject({ hostname: name, kind: "custom" });
      expect(added.verification_token).toBeUndefined();
      expect(added.record?.name).toBe(`_better-supabase.${name}`);
      expect(added.record?.value).toMatch(
        /^better-supabase-hostname-verification=[0-9a-f]{32}$/,
      );
      expect(
        (
          await s.value<Row>("better_supabase.add_hostname($1, $2)", [
            tenant,
            name,
          ])
        ).id,
      ).toBe(added.id);
      expect(
        await s.hint("better_supabase.add_hostname($1, 'not a host')", [
          tenant,
        ]),
      ).toBe("HOSTNAME_INVALID");
      expect(
        await s.hint("better_supabase.set_primary_hostname($1)", [added.id]),
      ).toBe("HOSTNAME_NOT_VERIFIED");

      await s.as(member);
      expect(
        await s.value<Row[]>("better_supabase.list_hostnames($1)", [tenant]),
      ).toHaveLength(1);
      expect(
        await s.hint("better_supabase.add_hostname($1, $2)", [tenant, host()]),
      ).toBe("HOSTNAME_FORBIDDEN");
      expect(
        await s.value<boolean>("better_supabase.remove_hostname($1)", [
          added.id,
        ]),
      ).toBe(false);
      expect(
        await s.hint("better_supabase.verify_hostname($1)", [added.id]),
      ).toBe("HOSTNAME_FORBIDDEN");

      // A rival's pending claim doesn't block the owner from verifying.
      await s.as(rival);

      const claim = await s.value<Row>("better_supabase.add_hostname($1, $2)", [
        other,
        name,
      ]);

      await s.service();
      expect(
        await s.hint("better_supabase.verify_hostname($1, $2)", [
          added.id,
          member.id,
        ]),
      ).toBe("HOSTNAME_NOT_FOUND");

      const admin = createDomainsAdmin({
        transport: sqlTransport(s.sql),
        resolver: () => Promise.resolve([added.record!.value]),
      });

      const done = await admin
        .verify(added.id, { actorId: owner.id })
        .orThrow();

      expect(done.verifiedAt).toBeDefined();
      expect(done.record).toBeUndefined();
      expect(
        await s.hint("better_supabase.verify_hostname($1)", [claim.id]),
      ).toBe("HOSTNAME_TAKEN");

      await s.as(owner);
      const domains = createDomains({ transport: sqlTransport(s.sql) });
      expect((await domains.setPrimary(added.id).orThrow()).primary).toBe(true);

      await s.as("anon");
      expect(await domains.resolve(`${name}:443`).orThrow()).toEqual({
        organizationId: tenant,
        hostname: name,
        primary: true,
        primaryHostname: name,
      });
      expect(await domains.resolve(host()).orThrow()).toBeUndefined();

      await s.service();

      const types = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where organization_id = $1 and type like 'hostname.%' order by position",
        [tenant],
      );

      expect(types.map((row) => row.type)).toEqual([
        "hostname.added",
        "hostname.verified",
        "hostname.primary_changed",
      ]);
    } finally {
      await s.close();
    }
  });

  it("verifies one label below platformDomain when added", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "domains", "reserved-slugs"], {
        modules: { domains: { options: { platformDomain: PLATFORM } } },
      });
      const owner = await s.user("owner");
      const rival = await s.user("rival");
      const tenant = await s.organization(owner);
      const other = await s.organization(rival);
      const label = `acme${crypto.randomUUID().slice(0, 6)}`;

      await s.as(owner);

      const sub = await s.value<Row>("better_supabase.add_hostname($1, $2)", [
        tenant,
        `${label}.${PLATFORM}`,
      ]);

      expect(sub.kind).toBe("subdomain");
      expect(sub.verified_at).not.toBeNull();
      expect(sub.record).toBeUndefined();
      expect(
        await s.hint("better_supabase.add_hostname($1, $2)", [
          tenant,
          PLATFORM,
        ]),
      ).toBe("HOSTNAME_RESERVED");
      expect(
        await s.hint("better_supabase.add_hostname($1, $2)", [
          tenant,
          `a.b.${PLATFORM}`,
        ]),
      ).toBe("HOSTNAME_INVALID");
      expect(
        await s.hint("better_supabase.add_hostname($1, $2)", [
          tenant,
          `admin.${PLATFORM}`,
        ]),
      ).toBe("HOSTNAME_RESERVED");

      await s.as(rival);
      expect(
        await s.hint("better_supabase.add_hostname($1, $2)", [
          other,
          `${label}.${PLATFORM}`,
        ]),
      ).toBe("HOSTNAME_TAKEN");
    } finally {
      await s.close();
    }
  });
});
