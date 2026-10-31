import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";
import { entryOf } from "../../fixtures/block-entry.ts";

const sqlOf = (
  names: readonly string[],
  options?: Readonly<Record<string, unknown>>,
): string =>
  renderBlocks(names, {
    modules: options ? { attachments: entryOf(options) } : {},
  })
    .filter((file) => file.module === "attachments")
    .map((file) => file.contents)
    .join("\n");

describe("attachments document types", () => {
  it("renders document types, the guard and the metadata-first functions", () => {
    const sql = sqlOf(["attachments"]);

    expect(sql).toContain("attachment_document_types");
    expect(sql).toContain("attachment_document_guard");
    expect(sql).toContain("claim_attachment_upload");
    expect(sql).toContain("mark_attachment_missing");
    expect(sql).toContain("bsb_attachments_external");
  });

  it("takes the source, external id and document type in create_attachment", () => {
    const sql = sqlOf(["attachments"]);

    expect(sql).toContain("document_type text default null");
    expect(sql).toContain("external_id text default null");
    expect(sql).toContain("source_path text default null");
    expect(sql).toContain(
      `drop function if exists "better_supabase"."create_attachment"(uuid, text, text, bigint, text, text, jsonb, integer, integer, integer);`,
    );
  });

  it("renders the attachment import target only with the imports block", () => {
    expect(sqlOf(["attachments"])).not.toContain("import_attachment");
    expect(sqlOf(["attachments", "imports"])).toContain(
      'function "better_supabase"."import_attachment"(run uuid, item jsonb, subject_id text)',
    );
  });

  it("allows the sources the app names", () => {
    expect(sqlOf(["attachments"], { sources: ["scanner", "mail"] })).toContain(
      "array['scanner', 'mail']::text[]",
    );
  });

  it("refuses a source with a character outside the pattern", () => {
    expect(() => sqlOf(["attachments"], { sources: ["Bad Source"] })).toThrow(
      /options\.sources/,
    );
  });

  it("checks the subject type against the registry", () => {
    expect(sqlOf(["attachments", "subjects"])).toContain('"subject_types"()');
  });
});
