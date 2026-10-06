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

  it("accepts any valid bucket id, short ones included", () => {
    const sql = sqlOf(["attachments"], {
      bucket: "ai",
      scanBuckets: ["x"],
      subjects: { note: { table: "notes", bucket: "files.v2" } },
    });
    expect(sql).toContain("'ai'");
    expect(sql).toContain("'files.v2'");
    for (const bucket of ["", "Upper", "-dash", "a/b", "a".repeat(101)]) {
      expect(() => sqlOf(["attachments"], { bucket })).toThrow(/bucket/);
    }
  });

  it("checks the subject on storage reads when files have subjects", () => {
    const visible = `"better_supabase"."attachment_object_visible"(bucket_id, name)`;
    expect(
      sqlOf(["attachments"], { subjects: { receipt: { table: "receipts" } } }),
    ).toMatch(
      new RegExp(
        `for select to authenticated\\n  using \\([^\\n]*'select'\\) and ${visible.replaceAll(/[.()"]/g, "\\$&")}\\);`,
      ),
    );
    expect(sqlOf(["attachments"])).not.toContain(`and ${visible}`);
  });

  it("gives subjects their own bucket and MIME types, a path template and a scan gate", () => {
    const sql = sqlOf(["attachments"], {
      path: "{organization_id}/{subject_type}/{id}",
      scanBuckets: ["files"],
      subjects: {
        receipt: {
          table: "receipts",
          bucket: "expenses",
          allowedMimeTypes: ["image/*"],
          cascade: true,
        },
        note: { table: "notes" },
      },
    });
    expect(sql).toContain(
      `"organization_id"::text || '/' || coalesce("subject_type", '-') || '/' || "id"::text`,
    );
    expect(sql).toContain("when 'receipt' then 'expenses'");
    expect(sql).toContain(`bucket_id in ('attachments', 'expenses')`);
    expect(sql).toContain(
      "values ('attachments', 'attachments', false, 52428800, null),\n  ('expenses', 'expenses', false, 52428800, array['image/*']::text[])",
    );
    expect(sql).toContain(
      `"subject_type" is distinct from 'receipt' or "mime_type" like 'image/%'`,
    );
    expect(sql).toContain("create trigger bs_object_scan_pending");
    expect(sql).toContain("when (new.bucket_id in ('files'))");
    expect(sql).toContain("bs_attachments_receipt_cascade");
    expect(sqlOf(["attachments"])).toContain(
      "drop trigger if exists bs_object_scan_pending on storage.objects;",
    );
    for (const [options, message] of [
      [{ path: "{organization_id}/x" }, /must contain \{id\}/],
      [
        { path: "{id}/{organization_id}" },
        /must start with \{organization_id\}/,
      ],
      [
        { path: "{organization_id}/{nope}/{id}" },
        /\{nope\} is not a placeholder/,
      ],
      [{ path: "{organization_id}/a b/{id}" }, /may hold letters/],
      [{ scanBuckets: ["Bad Bucket"] }, /is not a bucket id/],
      [{ subjects: { r: { table: "r", bucket: "B" } } }, /bucket must be/],
      [
        { subjects: { r: { table: "r", allowedMimeTypes: "x" } } },
        /allowedMimeTypes must be/,
      ],
    ] as const) {
      expect(() => sqlOf(["attachments"], options)).toThrow(message);
    }
  });
});
