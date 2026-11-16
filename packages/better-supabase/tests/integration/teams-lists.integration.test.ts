import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { createOrganizations } from "../../src/blocks/organizations/index.ts";
import { createTeams } from "../../src/blocks/teams/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)("teams and organization members lists", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("pages, searches, counts and reads one team", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const member = await s.user("member");
      await s.install(["organizations", "outbox", "audit", "teams"], {});
      const org = await s.organization(owner, { member });
      const transport = sqlTransport(s.sql);
      const teams = createTeams({ transport });
      const organizations = createOrganizations({ transport, tenant: org });

      await s.as(owner);

      const alpha = await teams
        .create({ organizationId: org, name: "Alpha", description: "Sales" })
        .orThrow();

      const beta = await teams
        .create({ organizationId: org, name: "Beta" })
        .orThrow();

      await teams.archive(beta.id).orThrow();

      const page = await teams
        .teamPage({ organizationId: org, sort: { by: "name" }, limit: 1 })
        .orThrow();

      expect(page.items).toHaveLength(1);
      expect(page.hasMore).toBe(true);

      const found = await teams
        .teamPage({ organizationId: org, q: "sales" })
        .orThrow();

      expect(found.items.map((row) => row.id)).toEqual([alpha.id]);

      const facets = await teams
        .teamFacets({ organizationId: org, facets: ["status"] })
        .orThrow();

      expect(facets[0]?.facet).toBe("status");
      expect(
        (await teams.teamCount({ organizationId: org }).orThrow()).value,
      ).toBe(2);
      expect((await teams.getTeam(alpha.id).orThrow()).name).toBe("Alpha");

      const members = await organizations
        .membersPage({ filters: { role: ["member"] } })
        .orThrow();

      expect(members.items.map((row) => row.userId)).toEqual([member.id]);
      expect((await organizations.membersCount().orThrow()).value).toBe(2);
    } finally {
      await s.close();
    }
  }, 60_000);
});
