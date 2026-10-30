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
      .saveCompany("o", { id: "c1", website: null, fields: { segment: "smb" } })
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
      .listPeople("o", { search: "acme", limit: 2 })
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
      .listCompanies("o")
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
    await parties.linkPerson("c1", "p1").orThrow();
    await parties.unlinkPerson("c1", "p1").orThrow();
    await parties.archivePerson("p1").orThrow();
    await parties.mergeCompanies("c1", "c2").orThrow();
    expect((await parties.mergePeople("p1", "p2").orThrow()).email).toBe(
      "ada@acme.com",
    );
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
    payment_terms_days: 30,
    credit_limit: "500000",
    credit_currency: "EUR",
    supplier_status: "approved",
  };

  it("reads the roles, terms, credit limit and supplier status", async () => {
    const t = transport({ list_companies: () => [SUPPLIER] });

    const page = await createContacts({ transport: t })
      .listCompanies("o", { role: "supplier", supplierStatus: "approved" })
      .orThrow();

    expect(t.calls[0]?.[1]).toMatchObject({
      role: "supplier",
      supplier_status: "approved",
    });
    expect(page.items[0]).toMatchObject({
      roles: ["customer", "supplier"],
      paymentTermsDays: 30,
      creditLimit: { amount: 500_000n, currency: "EUR" },
      supplierStatus: "approved",
      fields: { segment: "smb" },
    });
  });

  it("sends a credit limit as minor units and its currency", async () => {
    const t = transport({ save_person: () => PERSON });
    const parties = createContacts({ transport: t });

    await parties
      .savePerson("o", {
        id: "p1",
        paymentTermsDays: 14,
        creditLimit: { amount: 2500n, currency: "USD" },
      })
      .orThrow();
    await parties.savePerson("o", { id: "p1", creditLimit: null }).orThrow();

    expect(t.calls.map(([, args]) => args["attrs"])).toEqual([
      { paymentTermsDays: 14, creditLimit: "2500", creditCurrency: "USD" },
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
      .setRoles("c1", ["supplier", "customer"])
      .orThrow();

    const blocked = await parties
      .setSupplierStatus("p1", "blocked", "Late deliveries")
      .orThrow();

    await parties.setSupplierStatus("p1", null).orThrow();

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

    const result = await createContacts({ transport: t }).setRoles("c1", []);

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
      await parties.savePerson("o", { name: "Ada" }).orThrow(),
    ).toMatchObject({
      phone: "+31",
      ownerId: "u2",
      userId: "u3",
      mergedInto: "p9",
      archived: true,
    });
    const company = await parties.saveCompany("o", { name: "Acme" }).orThrow();
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
      .listCompanies("o", {
        lifecycle: "customer",
        ownerId: "u1",
        cursor: { name: "Acme", id: "c1" },
      })
      .orThrow();
    await parties.archiveCompany("c1", false).orThrow();
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
      .addIdentity("p1", { channel: "whatsapp", address: "+3161" })
      .orThrow();

    expect(added.verifiedAt).toBeUndefined();
    expect(await parties.removeIdentity("i1").orThrow()).toBe(false);
    expect(
      (await parties.findByIdentity("o", "whatsapp", "+3161").orThrow())?.id,
    ).toBe("p1");
    expect(
      await parties.findByIdentity("o", "whatsapp", "+3162").orThrow(),
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
      .representativesOf("client", "k1")
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
