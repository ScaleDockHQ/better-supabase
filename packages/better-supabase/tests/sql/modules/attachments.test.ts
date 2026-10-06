import { describe, expect, it } from "vitest";

import { renderModules } from "../../../src/sql/registry.ts";

const sqlOf = (
  names: readonly string[],
  options?: Readonly<Record<string, unknown>>,
): string =>
  renderModules(names, {
    modules: options ? { attachments: { options } } : {},
  })
    .filter((file) => file.module === "attachments")
    .map((file) => file.contents)
    .join("\n");

describe("attachments module", () => {
  it("creates a private bucket whose reads need a clean file", () => {
    const sql = sqlOf(["attachments"]);
    expect(sql).toMatch(/create table if not exists \S+attachments/);
    expect(sql).toContain(
      "values ('attachments', 'attachments', false, 52428800, null)",
    );
    expect(sql).toContain(`a."status" = 'clean'`);
    expect(sql).toContain(
      `create policy "bs_attachments_insert" on storage.objects`,
    );
    expect(sql).toContain("'attachments.upload'");
    expect(sql).toContain("'attachments.manage'");
    expect(sql).not.toContain("emit_event");
    expect(sql).not.toContain(`"status" = 'clean'\n  where`);
  });

  it("applies the bucket, size, type and scan options, and emits with the outbox", () => {
    const sql = sqlOf(["organizations", "outbox", "attachments"], {
      bucket: "files",
      maxSize: 1024,
      allowedMimeTypes: ["image/*", "application/pdf"],
      requireScan: false,
    });
    expect(sql).toContain(
      "values ('files', 'files', false, 1024, array['image/*', 'application/pdf']::text[])",
    );
    expect(sql).toContain(
      `"mime_type" like 'image/%' or "mime_type" = 'application/pdf'`,
    );
    expect(sql).toContain("between 0 and 1024");
    expect(sql).toContain(`a."status" in ('pending', 'clean', 'failed')`);
    expect(sql).toContain(`"status" = 'clean'\n  where`);
    expect(sql).toMatch(/emit_event\('attachment\.uploaded'/);
    expect(sql).toMatch(/emit_event\('attachment\.scanned'/);
  });

  it.each([
    [{ bucket: "Bad Bucket" }, /lowercase letters/],
    [{ maxSize: 0 }, /whole number of bytes/],
    [{ maxSize: 1.5 }, /whole number of bytes/],
  ])("rejects %j", (options, message) => {
    expect(() => sqlOf(["attachments"], options)).toThrow(message);
  });
});
