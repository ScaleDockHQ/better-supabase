import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { createAdvisories } from "../../src/blocks/advisories/index.ts";
import {
  advisoryListSurface,
  vulnerabilityListSurface,
} from "../../src/blocks/advisories/lists.ts";
import { createCustomFields } from "../../src/blocks/custom-fields/index.ts";
import { fieldDefinitionListSurface } from "../../src/blocks/custom-fields/lists.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";
import { smokeList } from "./list-smoke.ts";

const live = await reachable();

describe.skipIf(!live)("Y1 F14 lists in Postgres", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("pages the field definitions of a tenant", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(
        ["memberships", "permissions", "organizations", "custom-fields"],
        {},
      );
      const owner = await s.user("owner");
      const tenant = await s.organization(owner);

      const fields = createCustomFields({
        transport: sqlTransport(s.sql),
        tenant,
      });

      await s.asRole(owner);
      await fields
        .saveDefinition({
          entity: "contact",
          key: "plan",
          label: "Plan",
          type: "text",
        })
        .orThrow();

      expect(
        await smokeList({
          surface: fieldDefinitionListSurface,
          page: (options) => fields.page(options),
          facets: () => fields.facets(),
          count: () => fields.count(),
          get: (id) => fields.getDefinition(id),
        }),
      ).toBe(1);
    } finally {
      await s.close();
    }
  });

  it("pages advisories and vulnerabilities of a tenant", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(
        [
          "memberships",
          "permissions",
          "organizations",
          "subjects",
          "advisories",
        ],
        {},
      );
      const owner = await s.user("owner");
      const tenant = await s.organization(owner);

      const advisories = createAdvisories({
        transport: sqlTransport(s.sql),
        tenant,
      });

      await s.asRole(owner);

      const product = await advisories
        .saveProduct({ key: "core", name: "Core" })
        .orThrow();

      const vuln = await advisories
        .saveVulnerability({ vulnId: "CVE-2027-0001", summary: "Overflow" })
        .orThrow();

      await advisories
        .saveAdvisory({
          trackingId: "ADV-1",
          title: "Overflow in core",
          summary: "Fixed",
          productId: product.id,
          vulnerabilityIds: [vuln.id],
        })
        .orThrow();

      expect(
        await smokeList({
          surface: advisoryListSurface,
          page: (options) => advisories.page(options),
          facets: () => advisories.facets(),
          count: () => advisories.count(),
          get: (id) => advisories.getAdvisory(id),
        }),
      ).toBe(1);
      await smokeList({
        surface: vulnerabilityListSurface,
        page: (options) => advisories.pageVulnerabilities(options),
        facets: () => advisories.vulnerabilityFacets(),
        count: () => advisories.countVulnerabilities(),
      });
    } finally {
      await s.close();
    }
  });
});
