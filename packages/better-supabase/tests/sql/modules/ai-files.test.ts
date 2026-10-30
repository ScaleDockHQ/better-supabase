import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import {
  customContracts,
  moduleBody,
  renderBlocks,
} from "../../../src/sql/render.ts";
import { upgradePlan } from "../../../src/sql/upgrade.ts";

const body = (modules: AnyBlocksConfig = {}) =>
  moduleBody("ai-files", { modules })!;

const rendered = (names: readonly string[], modules: AnyBlocksConfig = {}) =>
  renderBlocks([...names, "ai-files"], { modules })
    .filter((file) => file.module === "ai-files")
    .map((file) => file.contents)
    .join("\n");

describe("ai-files module", () => {
  it("owns the file, provider file and document tables", () => {
    const sql = body();

    for (const table of [
      "ai_files",
      "ai_provider_files",
      "ai_documents",
      "ai_suggestions",
    ]) {
      expect(sql).toContain(
        `create table if not exists "better_supabase"."${table}" (`,
      );
    }

    expect(sql).not.toContain(`"better_supabase"."ai_document_versions"`);
    expect(sql).toContain(
      `"path" text generated always as ("organization_id"::text || '/' || "owner_id"::text || '/' || "id"::text || '/' || "filename") stored`,
    );
  });

  it("keeps document versions in the versions block", () => {
    const sql = body();

    expect(sql).toContain(
      `"better_supabase"."version_insert"(v_row."organization_id", 'ai_document', v_row."id"::text, jsonb_build_object('text', update_ai_document.content, 'messageId', update_ai_document.message_id), update_ai_document.storage_path, null, 'manual', false, auth.uid())`,
    );
    expect(sql).toContain(
      `delete from "better_supabase"."versions" x where x."subject_type" = 'ai_document' and x."subject_id" = old."id"::text;`,
    );
    expect(sql).toContain("after delete on");
  });

  it("hides AI document versions from the versions block's own reads", () => {
    const sql = renderBlocks(["ai-files"], { modules: {} })
      .filter((file) => file.module === "versions")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain(
      `create policy versions_ai_documents on "better_supabase"."versions" as restrictive`,
    );
    expect(sql).toContain(`and v_subject_type <> 'ai_document'`);
  });

  it("moves version 1 document versions onto the versions table", () => {
    const [plan] = upgradePlan([{ module: "ai-files", version: 1 }]);
    const sql = plan?.steps.map((step) => step.sql).join("\n") ?? "";

    expect(sql).toContain(
      `create table if not exists "better_supabase"."versions" (`,
    );
    expect(sql).toContain(
      `select doc."organization_id", 'ai_document', x.document_id::text, x.version`,
    );
    expect(sql).toContain(
      `drop table "better_supabase"."ai_document_versions" cascade;`,
    );
  });

  it("only accepts the upload a pending record of the caller expects", () => {
    const sql = body();
    expect(sql).toContain(
      `when 'insert' then a."status" = 'pending' and a."owner_id" = auth.uid()`,
    );
    expect(sql).toContain(
      `create policy bsb_ai_files_insert on storage.objects\n  for insert to authenticated`,
    );
    expect(sql).toContain("bucket_id = 'ai-files'");
  });

  it("checks permissions in read policies with a set", () => {
    const sql = body();

    const policy = sql.slice(
      sql.indexOf("create policy ai_files_read"),
      sql.indexOf("-- What a provider's file API"),
    );

    expect(policy).toContain(
      "better_supabase.tenant_ids_with('ai_files.manage')",
    );
    expect(policy).not.toContain("better_supabase.can(");
  });

  it("lets chat readers see a chat's files only with ai-chat installed", () => {
    expect(body()).not.toContain("ai_chat_can_read");
    const both = rendered(["ai-chat"], { "ai-chat": {} });
    expect(both).toContain('"better_supabase"."ai_chat_can_read"("chat_id")');
    expect(both).toContain(
      'not exists (select 1 from "better_supabase"."ai_chats"',
    );
  });

  it("creates a private bucket with the configured limits", () => {
    const sql = rendered([], {
      "ai-files": {
        options: {
          bucket: "chat-files",
          maxSize: 1024,
          allowedMimeTypes: ["image/*", "application/pdf"],
        },
      },
    });

    expect(sql).toContain(
      "values ('chat-files', 'chat-files', false, 1024, array['image/*', 'application/pdf']::text[])",
    );
    expect(sql).toContain("like any (array['image/%', 'application/pdf'])");
    expect(sql).toContain("between 0 and 1024");
  });

  it("rejects a bad bucket, size or media type", () => {
    const options = (value: Record<string, unknown>) => () =>
      moduleBody("ai-files", { modules: { "ai-files": { options: value } } });

    expect(options({ bucket: "Bad Bucket" })).toThrow(/bucket/);
    expect(options({ maxSize: -1 })).toThrow(/maxSize/);
    expect(options({ allowedMimeTypes: ["pdf"] })).toThrow(/MIME/);
  });

  it("keeps service writes to the service role", () => {
    const sql = body();

    for (const signature of [
      `"better_supabase"."store_ai_file"(uuid, uuid, text, text, bigint, uuid, text, text)`,
      `"better_supabase"."purge_ai_files"(interval, integer)`,
      `"better_supabase"."set_ai_provider_file"(uuid, text, text, timestamptz)`,
    ]) {
      expect(sql).toContain(
        `revoke execute on function ${signature} from public, anon, authenticated;`,
      );
    }
  });

  it("renders nothing in custom mode", () => {
    expect(
      moduleBody("ai-files", { modules: { "ai-files": { mode: "custom" } } }),
    ).toBeUndefined();
  });

  it("lists the functions a custom install has to provide", () => {
    const contract = customContracts(
      ["memberships", "permissions", "ai-files"],
      { modules: { "ai-files": { mode: "custom" } } },
    ).find((entry) => entry.module === "ai-files");

    const names = contract?.functions.map((fn) => fn.name) ?? [];
    expect(names).toContain("reserve_ai_file");
    expect(names).toContain("confirm_ai_file");
    expect(names).toContain("get_ai_file_by_path");
  });
});
