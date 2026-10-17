import { describe, expect, it } from "vitest";

import {
  createParties,
  partiesSubjects,
} from "../../../src/blocks/parties/index.ts";

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

    const company = await createParties({ transport: t })
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

    const parties = createParties({ transport: t });

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

    const page = await createParties({ transport: t })
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

    const parties = createParties({ transport: t });
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

  it("registers both tables as subjects", () => {
    const subjects = partiesSubjects({
      schema: "crm",
      url: { company: "/c/{id}" },
    });

    expect(subjects.company).toMatchObject({
      table: "crm.companies",
      idType: "uuid",
      url: "/c/{id}",
    });
    expect(subjects.person.url).toBeUndefined();
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

    const parties = createParties({
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

    const parties = createParties({ transport: t });
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

describe("parties block with the inbox", () => {
  it("links, unlinks and finds the person behind a contact", async () => {
    const t = transport({
      link_inbox_contact: () => true,
      unlink_inbox_contact: () => false,
      person_for_inbox_contact: (args) =>
        args["create"] === true ? PERSON : null,
    });

    const parties = createParties({ transport: t });
    expect(await parties.linkInboxContact("p1", "k1").orThrow()).toBe(true);
    expect(await parties.unlinkInboxContact("k1").orThrow()).toBe(false);
    expect(await parties.personForInboxContact("k1").orThrow()).toBeUndefined();
    expect(
      (await parties.personForInboxContact("k1", { create: true }).orThrow())
        ?.id,
    ).toBe("p1");
    expect(t.calls.map(([, args]) => args)).toEqual([
      { person: "p1", contact: "k1" },
      { contact: "k1" },
      { contact: "k1", create: false },
      { contact: "k1", create: true },
    ]);
  });
});
