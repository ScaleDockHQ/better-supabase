import { describe, expect, it } from "vitest";

import { createContacts } from "../../../src/blocks/contacts/index.ts";

function transport(
  results: Record<string, (args: Record<string, unknown>) => unknown>,
) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      calls.push([fn, args]);
      const result = results[fn];

      if (!result) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }

      return Promise.resolve(result(args));
    },
  };
}

const COMPANY = {
  id: "c1",
  tenant_id: "o",
  name: "Acme",
  domain: "acme.com",
  website: null,
  vat_id: null,
  lifecycle: "lead",
  owner_user_id: "u1",
  address: { city: "Utrecht" },
  merged_into: null,
  archived_at: null,
  created_by: "u1",
  created_at: "2026-10-14T00:00:00Z",
  updated_at: "2026-10-14T00:00:00Z",
  segment: "smb",
};

const PERSON = {
  id: "p1",
  tenant_id: "o",
  name: "Ada",
  email: "ada@acme.com",
  phone: null,
  title: "CTO",
  lifecycle: "lead",
  owner_user_id: null,
  user_id: null,
  merged_into: null,
  archived_at: null,
  created_by: "u1",
  created_at: "2026-10-14T00:00:00Z",
  updated_at: "2026-10-14T00:00:00Z",
};

describe("parties block", () => {
  it("sends only the keys a write sets, nulls and fields included", async () => {
    const t = transport({ save_company: () => COMPANY });

    const company = await createContacts({ transport: t })
      .saveCompany({
        organizationId: "o",
        input: { id: "c1", website: null, fields: { segment: "smb" } },
      })
      .orThrow();

    expect(t.calls[0]).toEqual([
      "save_company",
      { tenant: "o", company: "c1", attrs: { website: null, segment: "smb" } },
    ]);
    expect(company).toEqual({
      id: "c1",
      organizationId: "o",
      name: "Acme",
      lifecycle: "lead",
      archived: false,
      roles: [],
      ownerId: "u1",
      domain: "acme.com",
      address: { city: "Utrecht" },
      fields: { segment: "smb" },
    });
  });

  it("pages people by name and reads a company's people", async () => {
    const t = transport({
      list_people: () => [PERSON, { ...PERSON, id: "p2", name: "Bob" }],
      company_people_of: () => [
        { ...PERSON, role: "Champion", is_primary: true },
      ],
    });

    const parties = createContacts({ transport: t });

    const page = await parties
      .listPeople({ organizationId: "o", search: "acme", limit: 2 })
      .orThrow();

    expect(page.next).toEqual({ name: "Bob", id: "p2" });
    expect(t.calls[0]?.[1]).toEqual({
      tenant: "o",
      search: "acme",
      lifecycle: null,
      owner: null,
      after_name: null,
      after_id: null,
      page_size: 2,
      role: null,
      supplier_status: null,
    });
    const [person] = await parties.peopleOf("c1").orThrow();
    expect(person).toMatchObject({
      name: "Ada",
      role: "Champion",
      primary: true,
      fields: {},
    });
  });

  it("returns the last page without a cursor", async () => {
    const t = transport({ list_companies: () => [COMPANY] });

    const page = await createContacts({ transport: t })
      .listCompanies({ organizationId: "o" })
      .orThrow();

    expect(page.next).toBeUndefined();
    expect(page.items[0]?.name).toBe("Acme");
  });

  it("links, unlinks, archives and merges", async () => {
    const t = transport({
      set_company_person: () => true,
      remove_company_person: () => true,
      archive_person: () => true,
      merge_companies: () => COMPANY,
      merge_people: () => PERSON,
    });

    const parties = createContacts({ transport: t });
    await parties.linkPerson({ companyId: "c1", personId: "p1" }).orThrow();
    await parties.unlinkPerson({ companyId: "c1", personId: "p1" }).orThrow();
    await parties.archivePerson({ id: "p1" }).orThrow();
    await parties.mergeCompanies({ keep: "c1", drop: "c2" }).orThrow();
    expect(
      (await parties.mergePeople({ keep: "p1", drop: "p2" }).orThrow()).email,
    ).toBe("ada@acme.com");
    expect(t.calls.slice(0, 3)).toEqual([
      [
        "set_company_person",
        { company: "c1", person: "p1", role: null, is_primary: false },
      ],
      ["remove_company_person", { company: "c1", person: "p1" }],
      ["archive_person", { id: "p1", archived: true }],
    ]);
  });
});

describe("parties block, roles and suppliers", () => {
  const SUPPLIER = {
    ...COMPANY,
    roles: ["customer", "supplier"],
    customer_terms_id: "t1",
    credit_limit: "500000",
    credit_currency: "EUR",
    supplier_status: "approved",
  };

  it("reads the roles, terms, credit limit and supplier status", async () => {
    const t = transport({ list_companies: () => [SUPPLIER] });

    const page = await createContacts({ transport: t })
      .listCompanies({
        organizationId: "o",
        role: "supplier",
        supplierStatus: "approved",
      })
      .orThrow();

    expect(t.calls[0]?.[1]).toMatchObject({
      role: "supplier",
      supplier_status: "approved",
    });
    expect(page.items[0]).toMatchObject({
      roles: ["customer", "supplier"],
      customerTermsId: "t1",
      creditLimit: { amount: 500_000n, currency: "EUR" },
      supplierStatus: "approved",
      fields: { segment: "smb" },
    });
  });

  it("sends a credit limit as minor units and its currency", async () => {
    const t = transport({ save_person: () => PERSON });
    const parties = createContacts({ transport: t });

    await parties
      .savePerson({
        organizationId: "o",
        input: {
          id: "p1",
          customerTermsId: "t1",
          creditLimit: { amount: 2500n, currency: "USD" },
        },
      })
      .orThrow();
    await parties
      .savePerson({
        organizationId: "o",
        input: { id: "p1", creditLimit: null },
      })
      .orThrow();

    expect(t.calls.map(([, args]) => args["attrs"])).toEqual([
      { customerTermsId: "t1", creditLimit: "2500", creditCurrency: "USD" },
      { creditLimit: null, creditCurrency: null },
    ]);
  });

  it("sets roles and a supplier status on a company or a person", async () => {
    const t = transport({
      set_party_roles: () => ({ type: "company", party: SUPPLIER }),
      set_supplier_status: () => ({
        type: "person",
        party: { ...PERSON, roles: ["supplier"], supplier_status: "blocked" },
      }),
      supplier_status_from_qualifications: () => "conditional",
    });

    const parties = createContacts({ transport: t });

    const set = await parties
      .setRoles({ partyId: "c1", roles: ["supplier", "customer"] })
      .orThrow();

    const blocked = await parties
      .setSupplierStatus({
        partyId: "p1",
        status: "blocked",
        reason: "Late deliveries",
      })
      .orThrow();

    await parties.setSupplierStatus({ partyId: "p1", status: null }).orThrow();

    expect(set.type === "company" && set.company.roles).toEqual([
      "customer",
      "supplier",
    ]);
    expect(blocked.type === "person" && blocked.person.supplierStatus).toBe(
      "blocked",
    );
    expect(await parties.supplierStatusFromQualifications("c1").orThrow()).toBe(
      "conditional",
    );
    expect(t.calls).toEqual([
      ["set_party_roles", { party: "c1", roles: ["supplier", "customer"] }],
      [
        "set_supplier_status",
        { party: "p1", status: "blocked", reason: "Late deliveries" },
      ],
      ["set_supplier_status", { party: "p1", status: null, reason: null }],
      ["supplier_status_from_qualifications", { party: "c1" }],
    ]);
  });

  it("refuses a supplier status it doesn't know", async () => {
    const t = transport({
      set_party_roles: () => ({
        type: "company",
        party: { ...COMPANY, supplier_status: "pending" },
      }),
    });

    const result = await createContacts({ transport: t }).setRoles({
      partyId: "c1",
      roles: [],
    });

    expect(result.ok).toBe(false);
  });
});

describe("parties block, optional fields", () => {
  it("reads every optional field of a person and a company", async () => {
    const t = transport({
      save_person: () => ({
        ...PERSON,
        phone: "+31",
        owner_user_id: "u2",
        user_id: "u3",
        merged_into: "p9",
        archived_at: "2026-10-14T00:00:00Z",
      }),
      save_company: () => ({
        ...COMPANY,
        website: "https://acme.com",
        vat_id: "NL1",
        address: null,
      }),
    });

    const parties = createContacts({
      transport: t,
      logger: {
        error: () => undefined,
        warn: () => undefined,
        info: () => undefined,
        debug: () => undefined,
      },
      hooks: { savePerson: { after: () => undefined } },
    });

    expect(
      await parties
        .savePerson({ organizationId: "o", input: { name: "Ada" } })
        .orThrow(),
    ).toMatchObject({
      phone: "+31",
      ownerId: "u2",
      userId: "u3",
      mergedInto: "p9",
      archived: true,
    });

    const company = await parties
      .saveCompany({ organizationId: "o", input: { name: "Acme" } })
      .orThrow();

    expect(company).toMatchObject({
      website: "https://acme.com",
      vatId: "NL1",
    });
    expect(company.address).toBeUndefined();
    expect([t.calls[0]?.[1]["person"], t.calls[1]?.[1]["company"]]).toEqual([
      null,
      null,
    ]);
  });

  it("passes list filters and restores an archived company", async () => {
    const t = transport({
      list_companies: () => [],
      archive_company: () => true,
    });

    const parties = createContacts({ transport: t });
    await parties
      .listCompanies({
        organizationId: "o",
        lifecycle: "customer",
        ownerId: "u1",
        cursor: { name: "Acme", id: "c1" },
      })
      .orThrow();
    await parties.archiveCompany({ id: "c1", archived: false }).orThrow();
    expect(t.calls[0]?.[1]).toMatchObject({
      lifecycle: "customer",
      owner: "u1",
      after_name: "Acme",
      after_id: "c1",
    });
    expect(t.calls[1]?.[1]).toEqual({ id: "c1", archived: false });
  });
});

describe("person identities", () => {
  const IDENTITY = {
    id: "i1",
    tenant_id: "o",
    person_id: "p1",
    channel: "whatsapp",
    address: "+3161",
    verified_at: "2026-10-01T00:00:00Z",
    created_at: "2026-09-01T00:00:00Z",
  };

  it("lists, adds, removes and finds a person by an address", async () => {
    const t = transport({
      list_person_identities: () => [IDENTITY],
      add_person_identity: () => ({ ...IDENTITY, verified_at: null }),
      remove_person_identity: () => false,
      find_person_by_identity: (args) =>
        args["address"] === "+3161" ? PERSON : null,
    });

    const parties = createContacts({ transport: t });
    const [listed] = await parties.identities("p1").orThrow();
    expect(listed).toMatchObject({
      id: "i1",
      organizationId: "o",
      personId: "p1",
      channel: "whatsapp",
      address: "+3161",
    });
    expect(listed?.verifiedAt?.toString()).toBe("2026-10-01T00:00:00Z");

    const added = await parties
      .addIdentity({
        personId: "p1",
        identity: { channel: "whatsapp", address: "+3161" },
      })
      .orThrow();

    expect(added.verifiedAt).toBeUndefined();
    expect(await parties.removeIdentity("i1").orThrow()).toBe(false);
    expect(
      (
        await parties
          .findByIdentity({
            organizationId: "o",
            channel: "whatsapp",
            address: "+3161",
          })
          .orThrow()
      )?.id,
    ).toBe("p1");
    expect(
      await parties
        .findByIdentity({
          organizationId: "o",
          channel: "whatsapp",
          address: "+3162",
        })
        .orThrow(),
    ).toBeUndefined();
    expect(t.calls.map(([, args]) => args)).toEqual([
      { person: "p1" },
      { person: "p1", channel: "whatsapp", address: "+3161", verified: false },
      { identity: "i1" },
      { tenant: "o", channel: "whatsapp", address: "+3161" },
      { tenant: "o", channel: "whatsapp", address: "+3162" },
    ]);
  });
});

describe("parties block with relations", () => {
  const LINK = {
    id: "r1",
    organizationId: "o",
    personId: "p1",
    role: "guardian",
    authority: "act",
    validFrom: "2026-01-01",
    validUntil: null,
  };

  it("reads a record's representatives and the records a guest represents", async () => {
    const t = transport({
      list_representatives: () => [
        {
          ...LINK,
          name: "Ada",
          email: "ada@acme.com",
          phone: null,
          active: true,
          createdAt: "2026-10-14T00:00:00Z",
        },
      ],
      represented_by_me: () => [
        { ...LINK, subjectType: "client", subjectId: "k1" },
      ],
    });

    const parties = createContacts({ transport: t });

    const [representative] = await parties
      .representativesOf({ subjectType: "client", subjectId: "k1" })
      .orThrow();

    expect(representative).toMatchObject({
      personId: "p1",
      name: "Ada",
      email: "ada@acme.com",
      role: "guardian",
      authority: "act",
      active: true,
    });
    expect(representative?.validFrom?.toString()).toBe("2026-01-01");
    expect(representative).not.toHaveProperty("validUntil");
    expect(representative).not.toHaveProperty("phone");

    const [record] = await parties.representedByMe("o").orThrow();

    expect(record).toMatchObject({ subjectType: "client", subjectId: "k1" });
    expect(t.calls.map(([fn, args]) => [fn, args])).toEqual([
      ["list_representatives", { subject_type: "client", subject_id: "k1" }],
      ["represented_by_me", { tenant: "o" }],
    ]);
  });

  it("refuses a role it doesn't know", async () => {
    const t = transport({
      represented_by_me: () => [
        { ...LINK, role: "uncle", subjectType: "client", subjectId: "k1" },
      ],
    });

    const result = await createContacts({ transport: t }).representedByMe("o");

    expect(result.ok).toBe(false);
  });
});

describe("payment terms, credit block and delivery", () => {
  const TERM = {
    id: "t1",
    organizationId: "o",
    code: "NET30",
    name: "Net 30",
    days: 30,
    discountBps: 0,
    discountDays: 0,
    creditRestrictionBps: 0,
  };

  const PREFERENCE = {
    id: "d1",
    organizationId: "o",
    partyId: "c1",
    documentType: "invoice",
    channel: "post",
    copies: 2,
  };

  it("reads the terms columns of a company", async () => {
    const t = transport({
      save_company: () => ({
        ...COMPANY,
        customer_terms_id: "t1",
        supplier_terms_id: "t2",
        credit_block: "soft",
        language: "nl",
      }),
    });

    const company = await createContacts({ transport: t })
      .saveCompany({
        organizationId: "o",
        input: { id: "c1", customerTermsId: "t1", creditBlock: "soft" },
      })
      .orThrow();

    expect(t.calls[0]?.[1]).toMatchObject({
      attrs: { customerTermsId: "t1", creditBlock: "soft" },
    });
    expect(company).toMatchObject({
      customerTermsId: "t1",
      supplierTermsId: "t2",
      creditBlock: "soft",
      language: "nl",
    });
  });

  it("rejects an unknown credit block", async () => {
    const t = transport({
      save_company: () => ({ ...COMPANY, credit_block: "maybe" }),
    });

    await expect(
      createContacts({ transport: t })
        .saveCompany({ organizationId: "o", input: { id: "c1" } })
        .orThrow(),
    ).rejects.toThrow("credit block");
  });

  it("saves, lists and deletes payment terms", async () => {
    const t = transport({
      save_payment_term: () => TERM,
      list_payment_terms: () => [TERM],
      delete_payment_term: () => true,
    });

    const parties = createContacts({ transport: t });

    expect(
      await parties
        .savePaymentTerm({
          organizationId: "o",
          input: { code: "NET30", name: "Net 30" },
        })
        .orThrow(),
    ).toEqual(TERM);
    expect(await parties.paymentTerms("o").orThrow()).toEqual([TERM]);
    expect(await parties.deletePaymentTerm("t1").orThrow()).toBe(true);
    expect(t.calls[0]).toEqual([
      "save_payment_term",
      { tenant: "o", attrs: { code: "NET30", name: "Net 30" } },
    ]);
  });

  it("sets and lists delivery preferences", async () => {
    const t = transport({
      set_document_delivery_preferences: () => [PREFERENCE],
      list_document_delivery_preferences: () => [PREFERENCE],
    });

    const parties = createContacts({ transport: t });

    expect(
      await parties
        .setDeliveryPreferences({
          partyId: "c1",
          preferences: [
            { documentType: "invoice", channel: "post", copies: 2 },
          ],
        })
        .orThrow(),
    ).toEqual([PREFERENCE]);
    expect(await parties.deliveryPreferences("c1").orThrow()).toEqual([
      PREFERENCE,
    ]);
  });
});

describe("optional record keys", () => {
  it("reads every optional key of a person, an identity and a linked person", async () => {
    const full = {
      ...PERSON,
      phone: "+31 6 1234",
      user_id: "u9",
      avatar_url: "https://example.test/a.png",
      metadata: { source: "import" },
    };

    const t = transport({
      save_person: () => full,
      add_person_identity: () => ({
        id: "i1",
        tenant_id: "o",
        person_id: "p1",
        channel: "email",
        address: "ada@acme.com",
        verified_at: "2026-10-14T00:00:00Z",
        created_at: "2026-10-13T00:00:00Z",
      }),
      company_people_of: () => [{ ...full, is_primary: true, role: "billing" }],
    });

    const parties = createContacts({ transport: t });

    const person = await parties
      .savePerson({ organizationId: "o", input: { id: "p1" } })
      .orThrow();

    expect(person).toMatchObject({
      phone: "+31 6 1234",
      userId: "u9",
      avatarUrl: "https://example.test/a.png",
      metadata: { source: "import" },
    });

    const identity = await parties
      .addIdentity({
        personId: "p1",
        identity: { channel: "email", address: "ada@acme.com" },
      })
      .orThrow();

    expect(identity.verifiedAt).toBeDefined();
    expect(identity.createdAt).toBeDefined();
    expect(await parties.peopleOf("c1").orThrow()).toMatchObject([
      { primary: true, role: "billing", userId: "u9" },
    ]);
  });

  it("reads the dates and contact details of a representative", async () => {
    const t = transport({
      list_representatives: () => [
        {
          id: "r1",
          organizationId: "o",
          personId: "p1",
          role: "guardian",
          authority: "act",
          validFrom: "2026-01-01",
          validUntil: "2026-12-31",
          name: "Ada",
          active: true,
          email: "ada@acme.com",
          phone: "+31 6 1234",
          createdAt: "2026-01-01T00:00:00Z",
        },
      ],
    });

    const [representative] = await createContacts({ transport: t })
      .representativesOf({ subjectType: "company", subjectId: "c1" })
      .orThrow();

    expect(representative).toMatchObject({
      role: "guardian",
      email: "ada@acme.com",
      phone: "+31 6 1234",
    });
    expect(representative?.validFrom?.toString()).toBe("2026-01-01");
    expect(representative?.validUntil?.toString()).toBe("2026-12-31");
    expect(representative?.createdAt).toBeDefined();
  });
});
