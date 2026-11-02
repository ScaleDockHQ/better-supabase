import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { TestUser } from "./block-session.ts";

import { createLegalEntities } from "../../src/blocks/legal-entities/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)("legal-entities module in Postgres", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  let session: BlockSession;
  let owner: TestUser;
  let member: TestUser;
  let tenant: string;

  beforeAll(async () => {
    session = await BlockSession.open(pool);
    await session.install(
      ["organizations", "outbox", "settings", "numbering", "legal-entities"],
      { modules: { "legal-entities": { options: { on: ["numbering"] } } } },
    );
    owner = await session.user("legal-entities-owner");
    member = await session.user("legal-entities-member");
    tenant = await session.organization(owner, { member });
    await session.as(owner);
  });

  afterAll(async () => {
    await session.close();
    await pool.end();
  });

  it("makes the first entity the default and resolves a null entity to it", async () => {
    const entities = createLegalEntities({
      transport: sqlTransport(session.sql),
      tenant,
    });

    expect(await entities.of().orThrow()).toBeUndefined();

    const nl = await entities
      .create({ code: "NL01", name: "Acme B.V.", defaultCurrency: "EUR" })
      .orThrow();

    expect(nl.isDefault).toBe(true);
    expect(await entities.of().orThrow()).toBe(nl.id);

    const de = await entities
      .create({ code: "DE01", name: "Acme GmbH" })
      .orThrow();

    expect(de.isDefault).toBe(false);

    await entities.setDefault(de.id).orThrow();

    expect(await entities.of().orThrow()).toBe(de.id);
  });

  it("resolves a setting from the legal entity, then the organization", async () => {
    const entities = createLegalEntities({
      transport: sqlTransport(session.sql),
      tenant,
    });

    const [first] = await entities.list().orThrow();

    expect(first).toBeDefined();

    const id = first?.id ?? "";

    await entities
      .setSetting({ id, key: "invoice.footer", value: "Bedankt" })
      .orThrow();

    const resolved = await entities
      .resolveSetting({ key: "invoice.footer", legalEntityId: id })
      .orThrow();

    expect(resolved.source).toBe("legal_entity");
    expect(resolved.value).toBe("Bedankt");

    await entities.resetSetting({ id, key: "invoice.footer" }).orThrow();

    const fallback = await entities
      .resolveSetting({ key: "invoice.footer", legalEntityId: id })
      .orThrow();

    expect(fallback.source).not.toBe("legal_entity");
  });

  it("refuses a write from a member", async () => {
    await session.as(member);

    const entities = createLegalEntities({
      transport: sqlTransport(session.sql),
      tenant,
    });

    const result = await entities.create({ code: "FR01", name: "Acme SARL" });

    expect(result.ok).toBe(false);
    await session.as(owner);
  });

  it("adds a nullable legal_entity_id to the numbering table", async () => {
    const [row] = await session.rows<{ is_nullable: string }>(
      `select is_nullable from information_schema.columns
       where table_schema = 'better_supabase' and table_name = 'number_sequences'
         and column_name = 'legal_entity_id'`,
    );

    expect(row?.is_nullable).toBe("YES");
  });
});
