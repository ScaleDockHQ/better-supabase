import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { moduleBody, renderBlocks } from "../../../src/sql/render.ts";
import { upgradePlan } from "../../../src/sql/upgrade.ts";

const body = (modules: AnyBlocksConfig = {}) =>
  moduleBody("knowledge", { modules })!;

const rendered = (names: readonly string[], modules: AnyBlocksConfig = {}) =>
  renderBlocks([...names, "knowledge"], { modules })
    .filter((file) => file.module === "knowledge")
    .map((file) => file.contents)
    .join("\n");

describe("knowledge module", () => {
  it("owns the document and chunk tables with an hnsw and a gin index", () => {
    const sql = body();
    expect(sql).toContain(
      'create table if not exists "better_supabase"."knowledge_documents" (',
    );
    expect(sql).toContain(
      'create table if not exists "better_supabase"."knowledge_chunks" (',
    );
    expect(sql).toContain('"embedding" extensions.vector(1536)');
    expect(sql).toContain("using hnsw");
    expect(sql).toContain("extensions.vector_cosine_ops");
    expect(sql).toContain("using gin");
    expect(sql).toContain("to_tsvector('simple'::regconfig");
  });

  it("takes halfvec, more dimensions and another text search config", () => {
    const sql = body({
      knowledge: {
        options: { type: "halfvec", dimensions: 3072, textSearch: "english" },
      },
    });

    expect(sql).toContain('"embedding" extensions.halfvec(3072)');
    expect(sql).toContain("extensions.halfvec_cosine_ops");
    expect(sql).toContain("to_tsvector('english'::regconfig");
  });

  it("rejects a bad type, dimension count, config or queue", () => {
    const options = (value: Record<string, unknown>) => () =>
      moduleBody("knowledge", { modules: { knowledge: { options: value } } });

    expect(options({ type: "sparsevec" })).toThrow(/type/);
    expect(options({ dimensions: 3072 })).toThrow(/dimensions/);
    expect(options({ dimensions: 0 })).toThrow(/dimensions/);
    expect(options({ type: "halfvec", dimensions: 5000 })).toThrow(
      /dimensions/,
    );
    expect(options({ textSearch: "english; drop" })).toThrow(/textSearch/);
    expect(options({ embedQueue: "Bad-Queue" })).toThrow(/embedQueue/);
  });

  it("fuses vector and text ranks in an invoker search", () => {
    const sql = body();

    const search = sql.slice(
      sql.indexOf('function "better_supabase"."knowledge_search"'),
    );

    expect(search).toContain("security invoker");
    expect(search).toContain("1.0 / (60 + ");
    expect(search).toContain("'relaxed_order'");
  });

  it("keeps an embedding only while the content and model stay the same", () => {
    const sql = body();
    expect(sql).toContain("md5(");
    expect(sql).toContain("v_keep");
  });

  it("enqueues an embed job only with jobs installed", () => {
    expect(body()).not.toContain("enqueue_job");
    const withJobs = rendered(["queue"], { queue: {} });
    expect(withJobs).toContain(
      `"better_supabase"."enqueue_job"(queue => 'knowledge_embed'`,
    );

    const renamed = rendered(["queue"], {
      queue: {},
      knowledge: { options: { embedQueue: "embed" } },
    });

    expect(renamed).toContain(
      `"better_supabase"."enqueue_job"(queue => 'embed'`,
    );
  });

  it("links documents to files and chats only when those are installed", () => {
    expect(body()).not.toContain('"better_supabase"."ai_files"');
    expect(body()).not.toContain("ai_chat_can_read");

    const both = rendered(["ai-chat", "ai-files"], {
      "ai-chat": {},
      "ai-files": {},
    });

    expect(both).toContain('references "better_supabase"."ai_files"');
    expect(both).toContain('"better_supabase"."ai_chat_can_read"(');
  });

  it("keeps service functions to the service role", () => {
    const sql = body();

    for (const name of [
      "pending_knowledge_chunks",
      "set_knowledge_embeddings",
      "fail_knowledge_document",
      "pending_knowledge_documents",
      "reembed_knowledge",
    ]) {
      expect(sql).toMatch(
        new RegExp(
          `revoke execute on function "better_supabase"."${name}"\\([^)]*\\) from public, anon, authenticated;`,
        ),
      );
    }
  });

  it("queues a file's ingestion with ai-files and jobs", () => {
    expect(rendered(["ai-files"], { "ai-files": {} })).not.toContain(
      '"better_supabase"."queue_knowledge_file"(',
    );
    const sql = rendered(["ai-files", "queue"], { "ai-files": {}, queue: {} });
    expect(sql).toContain('"better_supabase"."queue_knowledge_file"(');
    expect(sql).toContain(
      `"better_supabase"."enqueue_job"(queue => 'knowledge_ingest'`,
    );
  });

  it("groups documents into collections with a visibility and grants", () => {
    const sql = body();

    expect(sql).toContain(
      'create table if not exists "better_supabase"."knowledge_collections" (',
    );
    expect(sql).toContain(
      'create table if not exists "better_supabase"."knowledge_collection_grants" (',
    );
    expect(sql).toContain("('automatic', 'restricted', 'disabled')");
    expect(sql).toContain('"collection_id" uuid');
    expect(sql).toContain('"knowledge_collection_readable"("id")');
    expect(sql).toContain("hint = 'KNOWLEDGE_VISIBILITY'");
    expect(sql).toContain("hint = 'KNOWLEDGE_GRANT'");
    expect(sql).toContain(
      '"set_knowledge_collection_grant"(uuid, uuid, text, boolean)',
    );
    expect(sql).not.toContain('"team_members"');
  });

  it("checks team grants against team members with teams installed", () => {
    const sql = rendered(["teams"]);

    expect(sql).toContain('"better_supabase"."team_members" tm');
  });

  it("keeps system documents tenant-free and shared with every tenant", () => {
    const sql = body();

    expect(sql).toContain("knowledge_documents_system_check");
    expect(sql).toContain('"organization_id" is null');
    expect(sql).toContain(
      'drop function if exists "better_supabase"."create_knowledge_document"(',
    );
    expect(sql).toContain("collections uuid[] default null");
    expect(sql).toContain("<> 'disabled'");
    expect(sql).toContain('"priority"');
  });

  it("drops the tenant not null when upgrading from version 2", () => {
    const [plan] = upgradePlan([{ module: "knowledge", version: 2 }]);
    const sql = plan?.steps.map((step) => step.sql).join("\n") ?? "";

    expect(sql).toContain('alter column "organization_id" drop not null');
  });
});
