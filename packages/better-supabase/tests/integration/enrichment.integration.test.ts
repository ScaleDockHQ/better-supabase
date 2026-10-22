import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { EnrichmentProvider } from "../../src/blocks/enrichment/index.ts";
import type { ModuleLayout } from "../../src/sql/module-types.ts";

import { createEnrichment } from "../../src/blocks/enrichment/index.ts";
import { createParties } from "../../src/blocks/parties/index.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { AsyncResult } from "../../src/core/result.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const layout: ModuleLayout = {
  subjects: withBlockSubjects({}, ["parties"], {}),
};

const MODULES = [
  "organizations",
  "outbox",
  "subjects",
  "parties",
  "enrichment",
];

const provider: EnrichmentProvider = {
  apiVersion: 1,
  name: "fake",
  company: (lookup) =>
    AsyncResult.ok(
      lookup.website === "https://acme.example"
        ? { name: "Acme", domain: "acme.example", industry: "software" }
        : undefined,
    ),
  person: (lookup) =>
    AsyncResult.ok(
      lookup.email === "ada@acme.example"
        ? { title: "CTO", phone: "+31 20 123 4567" }
        : undefined,
    ),
};

describe.skipIf(!live)("enrichment", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("stores provider results and fills empty columns", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const rep = await s.user("rep");
      await s.install(MODULES, layout);
      const org = await s.organization(owner, { member: rep });
      const transport = sqlTransport(s.sql);

      const parties = createParties({ transport });
      const enrichment = createEnrichment({ transport, provider });

      await s.as(owner);

      const acme = await parties
        .saveCompany(org, {
          name: "Acme",
          website: "https://acme.example",
          lifecycle: "lead",
        })
        .orThrow();

      const ada = await parties
        .savePerson(org, {
          name: "Ada",
          email: "ada@acme.example",
          title: "Engineer",
        })
        .orThrow();

      const nobody = await parties
        .saveCompany(org, {
          name: "Nobody",
          website: "https://nobody.example",
          lifecycle: "lead",
        })
        .orThrow();

      const company = await enrichment
        .enrich({ type: "company", id: acme.id })
        .orThrow();

      expect(company.status).toBe("matched");
      expect(company.filled).toEqual(["domain"]);
      expect(company.data).toMatchObject({ industry: "software" });

      const found = await parties
        .listCompanies(org, { search: "acme.example" })
        .orThrow();

      expect(found.items.map((c) => c.id)).toEqual([acme.id]);

      const person = await enrichment
        .enrich({ type: "person", id: ada.id })
        .orThrow();

      expect(person.filled).toEqual(["phone"]);

      await s.as(rep);

      const denied = await enrichment.enrich({
        type: "company",
        id: nobody.id,
      });

      expect(denied.error?.hint).toBe("ENRICHMENT_NOT_FOUND");

      const results = await enrichment
        .of({ type: "person", id: ada.id })
        .orThrow();

      expect(results.map((r) => r.provider)).toEqual(["fake"]);

      await s.service();
      const report = await enrichment.enrichDue({ limit: 10 }).orThrow();
      expect(report).toEqual({
        checked: 1,
        matched: 0,
        notFound: 1,
        failed: 0,
      });
      const again = await enrichment.enrichDue({ limit: 10 }).orThrow();
      expect(again.checked).toBe(0);
    } finally {
      await s.close();
    }
  });
});
