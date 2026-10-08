import { describe, expect, it } from "vitest";

import type { ModulesConfig } from "../../../src/config/modules.ts";

import { moduleBody, renderModules } from "../../../src/sql/registry.ts";

const body = (modules: ModulesConfig = {}) =>
  moduleBody("knowledge", { modules })!;

const rendered = (names: readonly string[], modules: ModulesConfig = {}) =>
  renderModules([...names, "knowledge"], { modules })
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
    const withJobs = rendered(["jobs"], { jobs: {} });
    expect(withJobs).toContain(
      `"better_supabase"."enqueue_job"(queue => 'knowledge_embed'`,
    );
    const renamed = rendered(["jobs"], {
      jobs: {},
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
});
