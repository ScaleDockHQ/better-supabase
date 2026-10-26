import { describe, expect, it } from "vitest";

import { withBlockSubjects } from "../../../src/config/block-subjects.ts";
import { renderBlocks } from "../../../src/sql/render.ts";
import { moduleProvider } from "../../fixtures/authorization-provider.ts";
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

describe("attachments module", () => {
  it("derives {ext} from the name in the generated path", () => {
    const sql = sqlOf(["attachments"], {
      path: "{organization_id}/attachments/{id}.{ext}",
    });

    expect(sql).toContain(
      `"id"::text || '.' || coalesce(substring(lower("name") from '\\.([a-z0-9]{1,10})$'), '')`,
    );
  });

  it("with offline, takes client ids, skips the scan and deletes objects from the queue", () => {
    const sql = sqlOf(["attachments"], { offline: true });

    expect(sql).toMatch(/grant insert \("id", "organization_id"/);
    expect(sql).toContain(`"status" = 'clean'`);
    expect(sql).toContain("after insert on storage.objects");
    expect(sql).toContain('before delete on "better_supabase"."attachments"');
    expect(sql).toContain(
      `using ((bucket_id in ('attachments') and "better_supabase"."attachment_object_queued"(bucket_id, name))`,
    );
    expect(sql).toContain(
      `grant execute on function "better_supabase"."queued_attachment_objects"(integer) to service_role;`,
    );
    expect(sql).toContain('create trigger "bsb_attachments_object_uploaded"');
  });

  it("with offline, keeps an explicit requireScan", () => {
    const sql = sqlOf(["attachments"], { offline: true, requireScan: true });

    expect(sql).not.toMatch(/"mime_type"\)\),?\s*"status" = 'clean'/);
    expect(sql).toContain(`a."status" = 'clean'`);
  });

  it("creates a private bucket whose reads need a clean file", () => {
    const sql = sqlOf(["attachments"]);
    expect(sql).toMatch(/create table if not exists \S+attachments/);
    expect(sql).toContain(
      "values ('attachments', 'attachments', false, 52428800, null)",
    );
    expect(sql).toContain(`a."status" = 'clean'`);
    expect(sql).toContain(
      `create policy bsb_attachments_insert on storage.objects`,
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

  it("lets a subject without a tenant decide its files' access", () => {
    const sql = sqlOf(["attachments"], {
      on: { note: { table: "notes", tenant: false } },
    });

    expect(sql).toContain(
      `alter table "better_supabase"."attachments" alter column "organization_id" drop not null;`,
    );
    expect(sql).toContain(`coalesce("organization_id"::text, '-')`);
    expect(sql).toContain(
      `when 'note' then exists (select 1 from "public"."notes" s where s."id"::text = attachment_subject_readable.subject_id)`,
    );
    expect(sql).toContain(
      `("organization_id" is null or coalesce(better_supabase.can(`,
    );
    expect(sqlOf(["attachments"])).not.toContain("drop not null");
    expect(() =>
      renderBlocks(["reactions"], {
        modules: {
          reactions: { on: { note: { table: "notes", tenant: false } } },
        },
      }),
    ).toThrow(/tenant can't be false/);
  });

  it("takes keys per subject type and checks a subject record's provider scope", () => {
    const sql = sqlOf(["attachments"], {
      on: {
        contract: {
          table: "contracts",
          permissions: { read: "contracts.read", upload: "contracts.edit" },
        },
      },
    });

    expect(sql).toContain(
      `("subject_type" = 'contract' and ("organization_id" in (select better_supabase.tenant_ids_with('contracts.read'))))`,
    );
    expect(sql).toContain(
      `case "subject_type" when 'contract' then 'contracts.edit' else 'attachments.upload' end`,
    );
    expect(sql).toContain(
      `case a."subject_type" when 'contract' then 'contracts.read' else 'attachments.read' end`,
    );
    expect(() =>
      sqlOf(["attachments"], {
        on: { contract: { table: "c", permissions: { write: "x" } } },
      }),
    ).toThrow(/use read, upload and manage/);

    const scoped = renderBlocks(["attachments"], {
      modules: {
        permissions: { model: "provider" },
        attachments: {
          on: { project: { table: "projects", scope: "project" } },
        },
      },
      accessProvider: moduleProvider,
    })
      .filter((file) => file.module === "attachments")
      .map((file) => file.contents)
      .join("\n");

    expect(scoped).toContain(
      `or "subject_id" in (select t.id::text from authz.ids_project('attachments.read') as t(id))`,
    );
    expect(scoped).toContain(
      `or a."subject_id" in (select t.id::text from authz.ids_project('attachments.manage') as t(id))`,
    );

    const withScope = (scope: unknown, provider: boolean) => () =>
      renderBlocks(["attachments"], {
        modules: {
          ...(provider ? { permissions: { model: "provider" } } : {}),
          attachments: { on: { project: { table: "projects", scope } } },
        },
        ...(provider ? { accessProvider: moduleProvider } : {}),
      });

    expect(withScope(1, true)).toThrow(/must be the name of a provider scope/);
    expect(withScope("project", false)).toThrow(
      /needs blocks.permissions.model "provider"/,
    );
    expect(withScope("organization", true)).toThrow(
      /"organization" is not a scope stub declares below its tenant scope "organization". Scopes: project/,
    );
  });

  it("takes upload and manage keys from the subject registry, and lets the block override them", () => {
    const render = (options?: Readonly<Record<string, unknown>>): string =>
      renderBlocks(["attachments"], {
        subjects: {
          contract: {
            table: "contracts",
            permissions: {
              read: "contracts.read",
              write: "contracts.write",
              upload: "contracts.edit",
              manage: "contracts.admin",
            },
          },
        },
        modules: options ? { attachments: entryOf(options) } : {},
      })
        .filter((file) => file.module === "attachments")
        .map((file) => file.contents)
        .join("\n");

    const sql = render();

    expect(sql).toContain(
      `case "subject_type" when 'contract' then 'contracts.edit' else 'attachments.upload' end`,
    );
    expect(sql).toContain("'contracts.admin'");
    expect(sql).not.toContain(
      `case a."subject_type" when 'contract' then 'contracts.read'`,
    );

    const overridden = render({
      on: {
        contract: {
          table: "contracts",
          permissions: { upload: "contracts.upload" },
        },
      },
    });

    expect(overridden).toContain(
      `case "subject_type" when 'contract' then 'contracts.upload' else 'attachments.upload' end`,
    );
    expect(overridden).toContain("'contracts.admin'");
  });

  it("checks the messaging key for files on a message or a comment thread", () => {
    const modules = ["messaging", "comments", "attachments"];

    const sql = renderBlocks(modules, {
      subjects: withBlockSubjects({}, modules, {}),
    })
      .filter((file) => file.module === "attachments")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain(
      `case "subject_type" when 'message' then 'messages.send' when 'conversation' then 'messages.send' else 'attachments.upload' end`,
    );
  });

  it("accepts any valid bucket id, short ones included", () => {
    const sql = sqlOf(["attachments"], {
      bucket: "ai",
      scanBuckets: ["x"],
      on: { note: { table: "notes", bucket: "files.v2" } },
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
      sqlOf(["attachments"], { on: { receipt: { table: "receipts" } } }),
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
      on: {
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
    expect(sql).toContain("create trigger bsb_object_scan_pending");
    expect(sql).toContain("when (new.bucket_id in ('files'))");
    expect(sql).toContain("bsb_attachments_receipt_cascade");
    expect(sqlOf(["attachments"])).toContain(
      "drop trigger if exists bsb_object_scan_pending on storage.objects;",
    );

    for (const [options, message] of [
      [{ path: "{organization_id}/x" }, /must contain \{id\}/],
      [
        { path: "{id}/{organization_id}" },
        /must start with \{organization_id\}/,
      ],
      [
        { path: "{organization_id}/{nope}/{id}" },
        /\{nope\} is not a placeholder\. Use .*\{ext\}/,
      ],
      [{ path: "{organization_id}/a b/{id}" }, /may hold letters/],
      [{ scanBuckets: ["Bad Bucket"] }, /is not a bucket id/],
      [{ on: { r: { table: "r", bucket: "B" } } }, /bucket must be/],
      [
        { on: { r: { table: "r", allowedMimeTypes: "x" } } },
        /allowedMimeTypes must be/,
      ],
    ] as const) {
      expect(() => sqlOf(["attachments"], options)).toThrow(message);
    }
  });

  it("rejects a version-like path, renders without metadata and nothing in custom mode", () => {
    expect(() =>
      sqlOf(["attachments"], { path: "{organization_id}/files/{id}-v2" }),
    ).toThrow(/-v and digits/);

    const bare = renderBlocks(["attachments"], {
      modules: {
        attachments: { columns: { attachments: { metadata: null } } },
      },
    })
      .filter((file) => file.module === "attachments")
      .map((file) => file.contents)
      .join("\n");

    expect(bare).toContain("create_attachment");
    expect(bare).not.toContain("create_attachment.metadata");
    expect(
      renderBlocks(["attachments"], {
        modules: { attachments: { mode: "custom" } },
      })
        .filter((file) => file.module === "attachments")
        .map((file) => file.contents)
        .join("\n"),
    ).not.toContain("create or replace function");
  });

  it("makes the listed buckets public only without the scan gate", () => {
    expect(sqlOf(["attachments"])).toContain(
      "on conflict (id) do update set public = excluded.public",
    );

    const sql = sqlOf(["attachments"], {
      publicBuckets: ["attachments"],
      requireScan: false,
    });

    expect(sql).toContain("'attachments', 'attachments', true");
    expect(() =>
      sqlOf(["attachments"], { publicBuckets: ["attachments"] }),
    ).toThrow("needs requireScan: false");
    expect(() =>
      sqlOf(["attachments"], { publicBuckets: ["other"], requireScan: false }),
    ).toThrow("is not one of the attachment buckets");
  });
});
