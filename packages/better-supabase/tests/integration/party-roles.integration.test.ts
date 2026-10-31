import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { Result } from "../../src/core/result.ts";

import { createContacts } from "../../src/blocks/contacts/index.ts";
import { createQualifications } from "../../src/blocks/qualifications/index.ts";
import { money } from "../../src/commerce/money.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = [
  "organizations",
  "outbox",
  "audit",
  "contacts",
  "qualifications",
];

const hint = (result: Result<unknown>): string =>
  result.ok ? "ok" : (result.error.hint ?? result.error.message);

describe.skipIf(!live)("party roles and suppliers", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("keeps roles, terms and a supplier status only an approver sets", async () => {
    const s = await BlockSession.open(pool);

    try {
      const owner = await s.user("owner");
      const buyer = await s.user("buyer");
      await s.install(MODULES);
      const org = await s.organization(owner, { member: buyer });
      const parties = createContacts({ transport: sqlTransport(s.sql) });

      const qualifications = createQualifications({
        transport: sqlTransport(s.sql),
      });

      await s.as(owner);

      const net30 = await parties
        .savePaymentTerm(org, { code: "NET30", name: "Net 30", days: 30 })
        .orThrow();

      await s.as(buyer);

      const acme = await parties
        .saveCompany(org, {
          name: "Acme",
          customerTermsId: net30.id,
          creditLimit: money(500_000n, "EUR"),
        })
        .orThrow();

      expect(acme).toMatchObject({ roles: [], customerTermsId: net30.id });
      expect(acme.creditLimit).toEqual(money(500_000n, "EUR"));
      expect(
        await parties
          .saveCompany(org, {
            name: "Bad",
            customerTermsId: crypto.randomUUID(),
          })
          .then(hint),
      ).toBe("PARTY_TERMS_INVALID");

      const set = await parties
        .setRoles(acme.id, ["supplier", "customer", "supplier"])
        .orThrow();

      expect(set.type === "company" ? set.company.roles : []).toEqual([
        "customer",
        "supplier",
      ]);
      expect(await parties.setRoles(acme.id, ["vendor"]).then(hint)).toBe(
        "PARTY_ROLES_INVALID",
      );

      const ada = await parties.savePerson(org, { name: "Ada" }).orThrow();
      await parties.setRoles(ada.id, ["funder"]).orThrow();

      expect(
        (
          await parties.listCompanies(org, { role: "supplier" }).orThrow()
        ).items.map((company) => company.name),
      ).toEqual(["Acme"]);
      expect(
        (await parties.listPeople(org, { role: "supplier" }).orThrow()).items,
      ).toEqual([]);

      expect(
        await parties.setSupplierStatus(acme.id, "approved").then(hint),
      ).toBe("PARTY_FORBIDDEN");

      await s.as(owner);
      expect(
        // @ts-expect-error a status the database refuses
        await parties.setSupplierStatus(acme.id, "trusted").then(hint),
      ).toBe("PARTY_SUPPLIER_STATUS_INVALID");

      const iso = await qualifications
        .saveType(org, {
          key: "iso9001",
          name: "ISO 9001 certificate",
          holderTypes: ["company"],
        })
        .orThrow();

      await qualifications.addRequirement(iso.id, "holder", acme.id).orThrow();

      expect(
        await parties.supplierStatusFromQualifications(acme.id).orThrow(),
      ).toBe("conditional");
      await qualifications
        .grant(org, {
          typeKey: "iso9001",
          holderType: "company",
          holderId: acme.id,
        })
        .orThrow();

      const status = await parties
        .supplierStatusFromQualifications(acme.id)
        .orThrow();

      expect(status).toBe("approved");
      await parties
        .setSupplierStatus(acme.id, status, "ISO 9001 certificate on file")
        .orThrow();
      await parties.setSupplierStatus(acme.id, status).orThrow();

      expect(
        (
          await parties
            .listCompanies(org, {
              role: "supplier",
              supplierStatus: "approved",
            })
            .orThrow()
        ).items.map((company) => company.supplierStatus),
      ).toEqual(["approved"]);

      await s.service();
      expect(
        await s.rows<{ data: unknown }>(
          "select payload as data from better_supabase.outbox_events where organization_id = $1 and type = 'company.supplier_status_changed'",
          [org],
        ),
      ).toEqual([
        {
          data: {
            organizationId: org,
            companyId: acme.id,
            name: "Acme",
            status: "approved",
            previousStatus: null,
            reason: "ISO 9001 certificate on file",
          },
        },
      ]);
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.audit_events where event_type = 'company.supplier_status_changed' and record_id = $1)",
          [acme.id],
        ),
      ).toBe(1);
    } finally {
      await s.close();
    }
  });
});
