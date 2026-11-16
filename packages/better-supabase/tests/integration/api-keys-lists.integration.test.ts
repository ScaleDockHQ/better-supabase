import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import {
  createApiKeys,
  sqlTransport,
} from "../../src/blocks/api-keys/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)("api key pages", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("pages the tenant's keys for a manager and the caller's own for a member", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "api-keys"]);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const organization = await s.organization(owner, { member });
      const keys = createApiKeys({ transport: sqlTransport(s.sql) });

      await s.as(owner);
      await keys.create({ name: "CI", organizationId: organization }).orThrow();

      await keys
        .create({ name: "Deploy", organizationId: organization })
        .orThrow();

      await s.as(member);

      await keys
        .create({ name: "Mine", organizationId: organization, personal: true })
        .orThrow();

      await s.as(owner);

      const all = await keys
        .keyPage({ organizationId: organization })
        .orThrow();

      expect(all.items).toHaveLength(3);

      const found = await keys
        .keyPage({ organizationId: organization, q: "deploy" })
        .orThrow();

      expect(found.items.map((row) => row.name)).toEqual(["Deploy"]);

      const first = await keys
        .keyPage({
          organizationId: organization,
          sort: { by: "name" },
          limit: 1,
        })
        .orThrow();

      expect(first.items.map((row) => row.name)).toEqual(["CI"]);
      expect(first.hasMore).toBe(true);

      expect(
        (await keys.keyCount({ organizationId: organization }).orThrow()).value,
      ).toBe(3);

      const facets = await keys
        .keyFacets({ organizationId: organization, facets: ["revoked"] })
        .orThrow();

      expect(facets[0]?.facet).toBe("revoked");

      await s.as(member);

      const own = await keys
        .keyPage({ organizationId: organization })
        .orThrow();

      expect(own.items.map((row) => row.name)).toEqual(["Mine"]);
      expect((await keys.keyPage().orThrow()).items).toHaveLength(1);
    } finally {
      await s.close();
    }
  }, 60_000);
});
