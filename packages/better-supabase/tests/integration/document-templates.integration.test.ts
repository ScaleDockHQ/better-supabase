import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { TestUser } from "./block-session.ts";

import { createDocumentTemplates } from "../../src/blocks/document-templates/index.ts";
import { createLegalEntities } from "../../src/blocks/legal-entities/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const RUN = "00000000-0000-4000-8000-0000000000f1";

describe.skipIf(!live)("document-templates module in Postgres", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  let session: BlockSession;
  let owner: TestUser;
  let tenant: string;

  beforeAll(async () => {
    session = await BlockSession.open(pool);
    await session.install([
      "organizations",
      "outbox",
      "settings",
      "numbering",
      "legal-entities",
      "document-templates",
    ]);
    owner = await session.user("document-templates-owner");
    tenant = await session.organization(owner);
    await session.as(owner);
  });

  afterAll(async () => {
    await session.close();
    await pool.end();
  });

  it("walks the fallback chain from entity and language to the organization", async () => {
    const entities = createLegalEntities({
      transport: sqlTransport(session.sql),
      tenant,
    });

    const templates = createDocumentTemplates({
      transport: sqlTransport(session.sql),
      tenant,
    });

    await entities.create({ code: "NL01", name: "Acme B.V." }).orThrow();

    const de = await entities
      .create({ code: "DE01", name: "Acme GmbH" })
      .orThrow();

    await templates
      .saveTemplate({ documentType: "quote", body: "<p>org</p>" })
      .orThrow();
    await templates
      .saveTemplate({
        documentType: "quote",
        body: "<p>de</p>",
        language: "de",
        legalEntityId: de.id,
      })
      .orThrow();

    const german = await templates
      .resolveTemplate({
        documentType: "quote",
        legalEntityId: de.id,
        language: "de-AT",
      })
      .orThrow();

    expect(german?.source).toBe("entity_language");

    const fallback = await templates
      .resolveTemplate({ documentType: "quote", language: "fr" })
      .orThrow();

    expect(fallback?.source).toBe("organization");
    expect(fallback?.body).toBe("<p>org</p>");
  });

  it("refuses a template with an unknown variable and names the hint", async () => {
    const hint = await session.hint(
      `select better_supabase.save_document_template($1, 'quote', '{{document.nope}}')`,
      [tenant],
    );

    expect(hint).toBe("DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE");
  });

  it("imports templates and text blocks as the service role, again without duplicates", async () => {
    await session.service();

    const item = {
      tenant,
      data: {
        documentType: "credit_note",
        body: "<p>{{document.number}}</p>",
        language: "nl",
        legalEntity: "NL01",
      },
    };

    const first = await session.value<{ subjectId: string }>(
      "better_supabase.import_document_template($1, $2::jsonb, null)",
      [RUN, JSON.stringify(item)],
    );

    const second = await session.value<{ subjectId: string }>(
      "better_supabase.import_document_template($1, $2::jsonb, $3)",
      [RUN, JSON.stringify(item), first.subjectId],
    );

    expect(second.subjectId).toBe(first.subjectId);

    const block = await session.value<{ subjectId: string }>(
      "better_supabase.import_document_text_block($1, $2::jsonb, null)",
      [
        RUN,
        JSON.stringify({
          tenant,
          data: { key: "footer", body: "Bedankt", language: "nl" },
        }),
      ],
    );

    expect(block.subjectId).toBeTruthy();

    const counted = await session.rows<{ count: string }>(
      `select count(*) from better_supabase.document_templates
       where tenant_id = $1 and document_type = 'credit_note'`,
      [tenant],
    );

    expect(counted[0]?.count).toBe("1");

    await session.as(owner);
  });
});
