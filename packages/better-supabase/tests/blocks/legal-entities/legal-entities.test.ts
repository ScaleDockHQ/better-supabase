import { describe, expect, it } from "vitest";

import {
  createLegalEntities,
  legalEntitiesBlock,
  legalEntityInputSchema,
} from "../../../src/blocks/legal-entities/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-30T10:00:00Z";

const ENTITY = {
  id: "le1",
  organizationId: "org-1",
  code: "NL01",
  name: "Acme B.V.",
  address: { city: "Utrecht" },
  vatNumber: "NL123456789B01",
  cocNumber: null,
  iban: "NL91ABNA0417164300",
  bic: null,
  logoAttachmentId: null,
  defaultCurrency: "EUR",
  fiscal: { fiscalYearStartMonth: 1, taxPeriod: "quarterly" },
  isDefault: true,
  archivedAt: null,
  createdAt: AT,
  updatedAt: AT,
};

const validate = (value: unknown) =>
  legalEntityInputSchema["~standard"].validate(value) as { issues?: unknown[] };

describe("createLegalEntities", () => {
  it("creates an entity in the request's organization", async () => {
    const t = fieldsTransport({ create_legal_entity: () => ENTITY });
    const entities = createLegalEntities({ transport: t, tenant: "org-1" });

    const created = await entities
      .create({ code: "NL01", name: "Acme B.V.", iban: "NL91ABNA0417164300" })
      .orThrow();

    expect(created.isDefault).toBe(true);
    expect(created.cocNumber).toBeNull();
    expect(created.fiscal).toEqual({
      fiscalYearStartMonth: 1,
      taxPeriod: "quarterly",
    });
    expect(created.createdAt.toString()).toBe("2026-10-30T10:00:00Z");
    expect(t.calls[0]).toEqual([
      "create_legal_entity",
      expect.objectContaining({
        tenant: "org-1",
        code: "NL01",
        iban: "NL91ABNA0417164300",
        is_default: false,
      }),
    ]);
  });

  it("sends only the changed fields as a patch", async () => {
    const t = fieldsTransport({ update_legal_entity: () => ENTITY });
    const entities = createLegalEntities({ transport: t, tenant: "org-1" });

    await entities
      .update("le1", {
        name: "Acme",
        vatNumber: null,
        fiscal: { taxPeriod: "monthly" },
      })
      .orThrow();

    expect(t.calls[0]).toEqual([
      "update_legal_entity",
      {
        legal_entity_id: "le1",
        patch: {
          name: "Acme",
          vat_number: null,
          fiscal: { taxPeriod: "monthly" },
        },
      },
    ]);
  });

  it("makes defaults, archives and restores", async () => {
    const t = fieldsTransport({
      set_default_legal_entity: () => ENTITY,
      set_legal_entity_archived: (args) => ({
        ...ENTITY,
        isDefault: false,
        archivedAt: args["archived"] === true ? AT : null,
      }),
    });

    const entities = createLegalEntities({ transport: t, tenant: "org-1" });

    await entities.setDefault("le1").orThrow();
    const archived = await entities.archive("le2").orThrow();
    const restored = await entities.restore("le2").orThrow();

    expect(archived.archivedAt?.toString()).toBe("2026-10-30T10:00:00Z");
    expect(restored.archivedAt).toBeNull();
  });

  it("lists and resolves entities", async () => {
    const t = fieldsTransport({
      list_legal_entities: () => [ENTITY],
      legal_entity_of: (args) => (args["id"] === "none" ? null : "le1"),
    });

    const entities = createLegalEntities({ transport: t, tenant: "org-1" });

    expect(
      await entities.list({ includeArchived: true }).orThrow(),
    ).toHaveLength(1);
    expect(await entities.of().orThrow()).toBe("le1");
    expect(await entities.of("none").orThrow()).toBeUndefined();
    expect(t.calls[0]?.[1]).toEqual({
      tenant: "org-1",
      include_archived: true,
    });
    expect(t.calls[1]?.[1]).toEqual({ tenant: "org-1", id: null });
  });

  it("reads, writes and resets an entity's settings", async () => {
    const t = fieldsTransport({
      get_legal_entity_settings: () => ({ "invoice.footer": "Thanks" }),
      set_legal_entity_setting: () => "Thanks",
      reset_legal_entity_setting: () => true,
    });

    const entities = createLegalEntities({ transport: t, tenant: "org-1" });

    expect(await entities.settings("le1").orThrow()).toEqual({
      "invoice.footer": "Thanks",
    });
    expect(
      await entities.setSetting("le1", "invoice.footer", "Thanks").orThrow(),
    ).toBe("Thanks");
    expect(await entities.resetSetting("le1", "invoice.footer").orThrow()).toBe(
      true,
    );
    expect(t.calls[1]?.[1]).toEqual({
      legal_entity_id: "le1",
      key: "invoice.footer",
      value: { value: "Thanks" },
    });
  });

  it("resolves a setting through the entity, the organization, then the default", async () => {
    const answers = [
      { value: "Thanks", source: "legal_entity", legalEntityId: "le1" },
      { value: 7, source: "organization", legalEntityId: null },
      { value: null, source: "default" },
      { value: "x", source: "unknown" },
    ];

    const queue = [...answers];

    const t = fieldsTransport({ resolve_setting: () => queue.shift() });

    const entities = createLegalEntities({ transport: t, tenant: "org-1" });

    expect(
      await entities
        .resolveSetting("invoice.footer", { legalEntityId: "le1" })
        .orThrow(),
    ).toEqual({
      source: "legal_entity",
      value: "Thanks",
      legalEntityId: "le1",
    });
    expect(await entities.resolveSetting("invoice.days").orThrow()).toEqual({
      source: "organization",
      value: 7,
      legalEntityId: undefined,
    });
    expect(await entities.resolveSetting("a").orThrow()).toEqual({
      source: "default",
      value: undefined,
      legalEntityId: undefined,
    });
    expect((await entities.resolveSetting("b").orThrow()).source).toBe(
      "default",
    );
    expect(t.calls[0]?.[1]).toEqual({
      tenant: "org-1",
      key: "invoice.footer",
      legal_entity: "le1",
    });
    expect(t.calls[1]?.[1]).toEqual({
      tenant: "org-1",
      key: "invoice.days",
      legal_entity: null,
    });
  });

  it("reads rows with missing or malformed fields", async () => {
    const t = fieldsTransport({
      list_legal_entities: () => [
        {
          ...ENTITY,
          address: "not an object",
          fiscal: { taxPeriod: "monthly" },
          archivedAt: AT,
        },
        { ...ENTITY, fiscal: "broken" },
      ],
    });

    const entities = createLegalEntities({ transport: t, tenant: "org-1" });
    const [first, second] = await entities.list().orThrow();

    expect(first?.address).toEqual({});
    expect(first?.fiscal).toEqual({
      fiscalYearStartMonth: 1,
      taxPeriod: "monthly",
    });
    expect(first?.archivedAt?.toString()).toBe("2026-10-30T10:00:00Z");
    expect(second?.fiscal).toEqual({
      fiscalYearStartMonth: 1,
      taxPeriod: "quarterly",
    });
  });

  it("sends every optional field on create and update", async () => {
    const t = fieldsTransport({
      create_legal_entity: () => ENTITY,
      update_legal_entity: () => ENTITY,
      get_legal_entity_settings: () => "not a record",
    });

    const entities = createLegalEntities({ transport: t, tenant: "org-1" });

    await entities
      .create({
        code: "NL02",
        name: "Beta B.V.",
        address: { city: "Delft" },
        vatNumber: "NL1",
        cocNumber: "123",
        iban: "NL2",
        bic: "ABNANL2A",
        logoAttachmentId: "att1",
        defaultCurrency: "EUR",
        fiscal: { fiscalYearStartMonth: 4, taxPeriod: "monthly" },
        isDefault: true,
      })
      .orThrow();
    await entities
      .update("le1", {
        code: "NL03",
        address: { city: "Breda" },
        cocNumber: "9",
        iban: "NL3",
        bic: null,
        logoAttachmentId: null,
        defaultCurrency: "USD",
      })
      .orThrow();

    expect(t.calls[0]?.[1]).toEqual(
      expect.objectContaining({
        coc_number: "123",
        bic: "ABNANL2A",
        logo_attachment_id: "att1",
        default_currency: "EUR",
        is_default: true,
      }),
    );
    expect(t.calls[1]?.[1]).toEqual({
      legal_entity_id: "le1",
      patch: expect.objectContaining({
        code: "NL03",
        coc_number: "9",
        bic: null,
        default_currency: "USD",
      }),
    });
    expect(await entities.settings("le1").orThrow()).toEqual({});
  });

  it("needs an organization to create or list", async () => {
    const entities = createLegalEntities({ transport: fieldsTransport({}) });
    const result = await entities.list();

    expect(result.ok).toBe(false);
  });
});

describe("legalEntitiesBlock", () => {
  it("names its SQL module and entity schema", () => {
    expect(legalEntitiesBlock.name).toBe("legal-entities");
    expect(legalEntitiesBlock.sql).toEqual(["legal-entities"]);
    expect(
      validate({ code: "NL01", fiscal: { taxPeriod: "monthly" } }).issues,
    ).toBeUndefined();
    expect(validate({ code: 5 }).issues).toBeDefined();
  });
});

describe("LegalEntities.disableCheck", () => {
  it("reports the numbers that stop a kind from going back to one series", async () => {
    const t = fieldsTransport({
      legal_entities_disable_check: () => ({
        ok: false,
        collisions: [
          {
            kind: "invoices",
            column: "number",
            value: "1",
            documents: 2,
            legalEntityIds: ["le1", "le2"],
          },
        ],
        defaultCollisions: [],
      }),
    });

    const entities = createLegalEntities({ transport: t, tenant: "org-1" });
    const check = await entities.disableCheck().orThrow();

    expect(check.ok).toBe(false);
    expect(check.collisions).toEqual([
      {
        kind: "invoices",
        column: "number",
        value: "1",
        documents: 2,
        legalEntityIds: ["le1", "le2"],
      },
    ]);
    expect(check.defaultCollisions).toEqual([]);
    expect(t.calls[0]).toEqual([
      "legal_entities_disable_check",
      { tenant: "org-1" },
    ]);
  });

  it("passes a clean answer and entries without entity ids", async () => {
    const t = fieldsTransport({
      legal_entities_disable_check: () => ({
        ok: true,
        collisions: [],
        defaultCollisions: [
          { kind: "quotes", column: "number", value: "7", documents: 2 },
        ],
      }),
    });

    const check = await createLegalEntities({ transport: t, tenant: "org-1" })
      .disableCheck()
      .orThrow();

    expect(check.ok).toBe(true);
    expect(check.defaultCollisions).toEqual([
      { kind: "quotes", column: "number", value: "7", documents: 2 },
    ]);
  });
});

describe("createLegalEntities with every field", () => {
  it("sends the address, numbers and logo, and null for the rest", async () => {
    const t = fieldsTransport({ create_legal_entity: () => ENTITY });
    const entities = createLegalEntities({ transport: t, tenant: "org-1" });

    await entities.create({ code: "NL01", name: "Acme" }).orThrow();
    await entities
      .create({
        code: "NL02",
        name: "Beta",
        address: { city: "Utrecht" },
        vatNumber: "NL1",
        cocNumber: "123",
        iban: "NL91",
        bic: "ABNANL2A",
        logoAttachmentId: "att1",
      })
      .orThrow();

    expect(t.calls[0]?.[1]).toMatchObject({
      address: null,
      vat_number: null,
      coc_number: null,
      bic: null,
      logo_attachment_id: null,
    });
    expect(t.calls[1]?.[1]).toMatchObject({
      vat_number: "NL1",
      coc_number: "123",
      bic: "ABNANL2A",
      logo_attachment_id: "att1",
    });
  });
});
