import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { moduleBody, renderBlocks } from "../../../src/sql/render.ts";
import { upgradePlan } from "../../../src/sql/upgrade.ts";

const body = (modules: AnyBlocksConfig = {}) =>
  moduleBody("memory", { modules })!;

const rendered = (names: readonly string[], modules: AnyBlocksConfig = {}) =>
  renderBlocks([...names, "memory"], { modules })
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
      'create table if not exists "better_supabase"."memory_message_embeddings" (',
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

  it("lets only admins change organization and record memory", () => {
    const sql = body();
    expect(sql).toContain("only admins change organization and record memory");
    expect(sql).toContain("v_scope in ('organization', 'record')");
    expect(sql).toContain("'memory.manage'");
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

  it("scopes memory to a record through its subject", () => {
    const sql = body();
    expect(sql).toContain('"subject_type" text,');
    expect(sql).toContain('"subject_id" text,');
    expect(sql).toContain(
      "constraint memories_owner_check check (\"scope\" in ('organization', 'record') or \"owner_id\" is not null)",
    );
    expect(sql).toContain("constraint memories_subject_check");
    expect(sql).toContain(
      "v_subject_id := nullif(memory_view.ns ->> 'subject_id', '');",
    );
    expect(sql).toContain('x."subject_id" is not distinct from v_subject_id');
    expect(sql).toContain('"project_id", "subject_type", "subject_id", "path"');
  });

  it("rejects the record scope when the table has no subject columns", () => {
    const sql = body({
      memory: { columns: { memories: { subjectType: null, subjectId: null } } },
    });

    expect(sql).not.toContain('"subject_id"');
    expect(sql).toContain("\n    or v_scope = 'record'");
  });

  it("saves a category, a confidence and an expiry", () => {
    const sql = body();
    expect(sql).toContain(
      'drop function if exists "better_supabase"."memory_save"(uuid, text, jsonb, extensions.vector, text, text);',
    );
    expect(sql).toContain(
      "category text default null,\n  confidence real default null,\n  expires_at timestamptz default null",
    );
    expect(sql).toContain("MEMORY_CONFIDENCE");
    expect(sql).toContain("MEMORY_CATEGORY");
    expect(sql).toContain(
      ", memory_save.category, memory_save.confidence, memory_save.expires_at)",
    );
  });

  it("weighs search by confidence and counts uses", () => {
    const sql = body();
    expect(sql).toContain('r.score * coalesce(t."confidence", 1) as score');
    expect(sql).toContain(
      'set "use_count" = t."use_count" + 1, "last_used_at" = now()',
    );
    expect(sql).toContain('x."expires_at" > now()');
  });

  it("soft deletes, restores and purges memories", () => {
    const sql = body();
    expect(sql).toContain(
      'update "better_supabase"."memories" x set "deleted_at" = now(), "updated_at" = now()',
    );
    expect(sql).toContain('function "better_supabase"."memory_restore"(');
    expect(sql).toContain('function "better_supabase"."purge_memories"(');
    expect(sql).toContain(
      'where "path" is not null and "superseded_by" is null and "deleted_at" is null;',
    );
    expect(sql).toContain('set "deleted_at" = coalesce(x."deleted_at", now())');
  });

  it("hard deletes and skips use counts when the columns are gone", () => {
    const sql = body({
      memory: {
        columns: {
          memories: {
            deletedAt: null,
            expiresAt: null,
            useCount: null,
            lastUsedAt: null,
            confidence: null,
            category: null,
          },
        },
      },
    });

    expect(sql).not.toContain("memory_restore");
    expect(sql).not.toContain("used as (");
    expect(sql).not.toContain('y."expires_at" > now()');
    expect(sql).toContain("as score\n    from (");
    expect(sql).toContain(
      'delete from "better_supabase"."memories" x\n  where',
    );
  });

  it("upgrades version 2 memories in place", () => {
    const [plan] = upgradePlan([{ module: "memory", version: 2 }]);
    expect(plan?.to).toBe(5);
    const sql = plan?.steps.map((step) => step.sql).join("\n") ?? "";
    expect(sql).toContain('add column if not exists "subject_type" text');
    expect(sql).toContain(
      'add column if not exists "use_count" integer not null default 0',
    );
    expect(sql).toContain("memories_scope_check");
    expect(sql).toContain("add constraint memories_owner_check");
    expect(sql).toContain("c.relname = 'memories_path_idx'");
  });

  it("gives organization and record memory an owner with ns.private", () => {
    const sql = body();
    expect(sql).toContain(
      "v_private := coalesce((memory_view.ns ->> 'private')::boolean, false);",
    );
    expect(sql).toContain(
      "v_owner := case when v_scope in ('organization', 'record') and not v_private then null",
    );
    expect(sql).toContain(
      "or (v_owner is null and (v_scope not in ('organization', 'record') or v_private))",
    );
    expect(sql).toContain("if v_owner is null and not (");
    expect(sql).toMatch(
      /\("owner_id" = \(select auth\.uid\(\)\) or \("owner_id" is null and /,
    );
  });

  it("lets personal memory have no tenant with options.tenant false", () => {
    const shared = body();
    expect(shared).toContain('"organization_id" uuid not null,');
    expect(shared).toContain('x."organization_id" = memory_view.tenant');

    const sql = body({ memory: { options: { tenant: false } } });
    expect(sql).toContain('"organization_id" uuid,');
    expect(sql).toContain(
      'alter table "better_supabase"."memories" alter column "organization_id" drop not null;',
    );
    expect(sql).toContain(
      'x."organization_id" is not distinct from memory_view.tenant',
    );
    expect(sql).toContain(
      "or (memory_view.tenant is null and v_owner is null)",
    );
    expect(sql).toContain("(memory_view.tenant is null or ");
  });

  it("caps archival facts with options.maxItems", () => {
    expect(body()).not.toContain("offset ");

    const sql = body({ memory: { options: { maxItems: 50 } } });
    expect(sql).toContain("offset 50");
    expect(sql).toContain(
      'y."organization_id" is not distinct from memory_save.tenant and y."owner_id" is not distinct from v_owner',
    );
    expect(sql).toContain(
      'update "better_supabase"."memories" x set "deleted_at" = now(), "updated_at" = now()',
    );
    expect(() => body({ memory: { options: { maxItems: 0 } } })).toThrow(
      "maxItems must be a positive whole number",
    );
  });

  it("purges one tenant's memories", () => {
    const sql = body();
    expect(sql).toContain(
      'drop function if exists "better_supabase"."purge_memories"(integer, integer);',
    );
    expect(sql).toContain(
      '"purge_memories"(retention_days integer default 30, batch integer default 1000, tenant uuid default null)',
    );
    expect(sql).toContain(
      'purge_memories.tenant is null or y."organization_id" = purge_memories.tenant',
    );
  });

  it("upgrades version 3 memories to owners on shared scopes", () => {
    const [plan] = upgradePlan([{ module: "memory", version: 3 }]);
    expect(plan?.to).toBe(5);
    const sql = plan?.steps.map((step) => step.sql).join("\n") ?? "";
    expect(sql).toContain(
      "add constraint memories_owner_check check (\"scope\" in ('organization', 'record') or \"owner_id\" is not null);",
    );
  });
});
