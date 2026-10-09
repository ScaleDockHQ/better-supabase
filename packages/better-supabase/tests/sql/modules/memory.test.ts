import { describe, expect, it } from "vitest";

import type { ModulesConfig } from "../../../src/config/modules.ts";

import { moduleBody, renderModules } from "../../../src/sql/registry.ts";

const body = (modules: ModulesConfig = {}) =>
  moduleBody("memory", { modules })!;

const rendered = (names: readonly string[], modules: ModulesConfig = {}) =>
  renderModules([...names, "memory"], { modules })
    .filter((file) => file.module === "memory")
    .map((file) => file.contents)
    .join("\n");

describe("memory module", () => {
  it("owns the memory and message embedding tables", () => {
    const sql = body();
    expect(sql).toContain(
      'create table if not exists "better_supabase"."memories" (',
    );
    expect(sql).toContain(
      'create table if not exists "better_supabase"."ai_message_embeddings" (',
    );
    expect(sql).toContain("nulls not distinct");
    expect(sql).toContain("using hnsw");
  });

  it("keeps core memory under /memories without dot segments", () => {
    const sql = body();
    expect(sql).toContain("'^/memories(/[A-Za-z0-9._ -]+)*$'");
    expect(sql).toContain("'(^|/)[.]{1,2}(/|$)'");
  });

  it("implements the memory tool commands with version checks", () => {
    const sql = body();
    for (const name of [
      "memory_view",
      "memory_create",
      "memory_str_replace",
      "memory_insert",
      "memory_delete",
      "memory_rename",
    ]) {
      expect(sql).toContain(`function "better_supabase"."${name}"(`);
    }
    expect(sql).toContain("MEMORY_CONFLICT");
    expect(sql).toContain("MEMORY_AMBIGUOUS");
    expect(sql).toContain("MEMORY_NO_MATCH");
  });

  it("lets only admins change organization memory", () => {
    const sql = body();
    expect(sql).toContain("only admins change organization memory");
    expect(sql).toContain("'ai.admin'");
  });

  it("caps content at maxContent and rejects a bad cap", () => {
    expect(body({ memory: { options: { maxContent: 500 } } })).toContain(
      'length("content") <= 500',
    );
    expect(() =>
      moduleBody("memory", {
        modules: { memory: { options: { maxContent: 0 } } },
      }),
    ).toThrow(/maxContent/);
  });

  it("skips temporary chats and cascades with ai-chat installed", () => {
    expect(body()).not.toContain("is_temporary");
    const both = rendered(["ai-chat"], { "ai-chat": {} });
    expect(both).toContain('"is_temporary"');
    expect(both).toContain(
      'references "better_supabase"."ai_chats" ("id") on delete cascade',
    );
  });

  it("puts hnsw.iterative_scan back after a vector search", () => {
    const sql = body();
    for (const name of ["memory_search", "recall_ai_messages"]) {
      const start = sql.indexOf(`function "better_supabase"."${name}"(`);
      const fn = sql.slice(
        start,
        sql.indexOf("$$;", sql.indexOf("as $$", start)),
      );
      expect(fn).toContain("volatile");
      expect(fn).not.toMatch(/^stable$/m);
      expect(fn).toContain(
        "set_config('hnsw.iterative_scan', coalesce(nullif(v_scan, ''), 'off'), true)",
      );
    }
  });

  it("keeps embedding writes to the service role", () => {
    const sql = body();
    for (const name of [
      "set_memory_embedding",
      "set_memory_embeddings",
      "pending_memory_embeddings",
      "set_ai_message_embedding",
    ]) {
      expect(sql).toMatch(
        new RegExp(
          `revoke execute on function "better_supabase"."${name}"\\([^)]*\\) from public, anon, authenticated;`,
        ),
      );
    }
  });
});
