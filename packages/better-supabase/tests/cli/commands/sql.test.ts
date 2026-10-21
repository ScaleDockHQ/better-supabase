import { parseArgs } from "citty";
import {
  mkdir,
  mkdtemp,
  readdir,
  readFile,
  rm,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { migrationsDir, runSql } from "../../../src/cli/commands/sql.ts";
import { SQL_ARGS } from "../../../src/cli/sql/args.ts";
import {
  type BetterSupabaseConfig,
  resolveConfig,
} from "../../../src/config/index.ts";
import {
  modulePermissionKeys,
  renderModules,
  SQL_MODULES,
  moduleLayout,
} from "../../../src/sql/index.ts";
import {
  stubProvider,
  withProvider,
} from "../../fixtures/authorization-provider.ts";
import { inputRequired, usageError } from "../fixtures/usage.ts";

describe("moduleLayout", () => {
  it("turns expose into grants per role and json schemas into column checks", () => {
    const config = resolveConfig(
      {
        expose: {
          "public.posts": {
            anon: ["select"],
            authenticated: ["select", "insert"],
          },
          "public.notes": ["select"],
        },
        json: {
          "public.posts.meta": { type: "Meta", schema: { type: "object" } },
          "public.posts.raw": { type: "unknown" },
        },
        plugins: { tenant: { column: "org_id" } },
      },
      "/p",
    );

    const layout = moduleLayout(config, "tests/sql");
    const all = ["select", "insert", "update", "delete"];
    expect(layout.grants).toEqual([
      { table: "public.posts", role: "anon", privileges: ["select"] },
      {
        table: "public.posts",
        role: "authenticated",
        privileges: ["select", "insert"],
      },
      { table: "public.posts", role: "service_role", privileges: all },
      { table: "public.notes", role: "anon", privileges: [] },
      { table: "public.notes", role: "authenticated", privileges: ["select"] },
      { table: "public.notes", role: "service_role", privileges: all },
    ]);
    expect(layout.functionGrants).toEqual([]);
    expect(layout.jsonSchemas).toEqual([
      { table: "public.posts", column: "meta", schema: { type: "object" } },
    ]);
    expect(layout).toMatchObject({
      testsDir: "tests/sql",
      tenantColumn: "org_id",
    });
    expect(layout).not.toHaveProperty("accessProvider");
    expect(layout).not.toHaveProperty("version");
  });
});

describe("runSql", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "better-supabase-sql-"));
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  const sql = (argv: string[], config: BetterSupabaseConfig = {}) =>
    runSql(resolveConfig(config, root), parseArgs(argv, SQL_ARGS));

  it("asks for an action and rejects unknown ones", async () => {
    expect(await usageError(() => sql([]))).toBe("Name a subcommand.");
    expect(await usageError(() => sql(["drop"]))).toBe(
      'Unknown sql subcommand "drop".',
    );
  });

  it("asks for module names", async () => {
    const add = await inputRequired(() => sql(["add"]));

    expect(add.problem.missing).toEqual(["<module>"]);
    expect(add.problem.choices?.["<module>"]).toEqual(Object.keys(SQL_MODULES));
    expect((await inputRequired(() => sql(["print"]))).problem.missing).toEqual(
      ["<module>"],
    );
    const names = Object.keys(SQL_MODULES).join(", ");
    expect(await usageError(() => sql(["print", "nope"]))).toBe(
      `Name one module: ${names}`,
    );
  });

  it("adds a module next to the ones blocks lists", async () => {
    const config: BetterSupabaseConfig = { blocks: ["organizations"] };

    const added = await sql(["add", "billing"], config);
    expect(added.output).toContain("(billing)");
    expect(added.output).not.toContain("(organizations)");

    const path = /Created (supabase\/schemas\/\S+) \(billing\)/.exec(
      added.output ?? "",
    )?.[1];

    const billing = await readFile(join(root, path ?? "missing"), "utf-8");
    expect(billing).toContain("billing_customers_tenant_fkey");
  });

  it("lists added modules in the config file, or prints them when it can't", async () => {
    const run = (argv: string[], configFile?: string) =>
      runSql(resolveConfig({}, root), parseArgs(argv, SQL_ARGS), undefined, {
        now: () => new Date("2026-10-15T00:00:00Z"),
        ...(configFile === undefined ? {} : { configFile }),
      });

    expect((await run(["add", "updated-at"])).output).toContain(
      'Add them to blocks in better-supabase.config.ts so `sql sync --check` keeps them current:\n  "updated-at": {},',
    );

    const file = join(root, "better-supabase.config.ts");
    await writeFile(file, "export default defineConfig(base);\n");
    const refused = await run(["add", "updated-at"], file);
    expect(refused.output).toContain(
      "better-supabase.config.ts wasn't changed: it doesn't pass an object literal to defineConfig().",
    );

    const literal = "export default defineConfig({ blocks: { audit: {} } });\n";
    await writeFile(file, literal);
    const dry = await run(["add", "updated-at", "--dry-run"], file);
    expect(dry.output).toContain(
      "Would add updated-at to blocks in better-supabase.config.ts.",
    );
    expect(await readFile(file, "utf-8")).toBe(literal);
    const added = await run(["add", "updated-at"], file);
    expect(added.output).toContain(
      "Added updated-at to blocks in better-supabase.config.ts.",
    );
    expect(await readFile(file, "utf-8")).toBe(
      'export default defineConfig({ blocks: { audit: {}, "updated-at": {} } });\n',
    );
  });

  it("writes and checks the topic policies of realtime.policies", async () => {
    const realtime = resolve(
      import.meta.dirname,
      "../../../src/realtime/index.ts",
    );

    await writeFile(
      join(root, "topics.ts"),
      `import { defineTopic } from ${JSON.stringify(realtime)};
export const rooms = defineTopic("room:{roomId}", { send: true });
export const boards = defineTopic("board:{boardId}");
export const notATopic = { template: "x" };
`,
    );

    const config: BetterSupabaseConfig = {
      realtime: {
        policies: {
          from: ["topics.ts"],
          output: "supabase/schemas/905_topics.sql",
        },
      },
    };

    expect((await sql(["sync"], config)).output).toBe(
      "Created supabase/schemas/905_topics.sql (topics)",
    );

    const written = await readFile(
      join(root, "supabase/schemas/905_topics.sql"),
      "utf-8",
    );

    expect(written.indexOf("topic board:{boardId}")).toBeLessThan(
      written.indexOf("topic room:{roomId}"),
    );
    expect(written).toContain('create policy "bs_topic_room_send"');
    expect((await sql(["sync", "--check"], config)).code).toBe(0);
    await writeFile(
      join(root, "supabase/schemas/905_topics.sql"),
      "-- edited\n",
    );
    const stale = await sql(["sync", "--check"], config);
    expect(stale.code).toBe(1);
    expect(stale.error).toContain("supabase/schemas/905_topics.sql");
    await writeFile(join(root, "empty.ts"), "export const x = 1;\n");
    await expect(
      sql(["sync"], {
        realtime: { policies: { from: ["empty.ts"], output: "out.sql" } },
      }),
    ).rejects.toThrow(/exports no topic/);
  });

  it("writes the broadcast triggers of realtime.triggers after the policies", async () => {
    const realtime = resolve(
      import.meta.dirname,
      "../../../src/realtime/index.ts",
    );

    await writeFile(
      join(root, "topics.ts"),
      `import { defineTopic } from ${JSON.stringify(realtime)};
export const quotes = defineTopic("organization:{organizationId}:quotes");
`,
    );
    const output = "supabase/schemas/905_topics.sql";
    const policies = { from: ["topics.ts"], output };

    const triggers = [
      {
        topic: "organization:{organizationId}:quotes",
        table: "public.quotes",
        event: "quote.changed",
      },
    ];

    await sql(["sync"], {
      realtime: { policies, triggers },
      blocks: ["realtime-tables"],
    });
    const written = await readFile(join(root, output), "utf-8");
    expect(written.indexOf("create policy")).toBeLessThan(
      written.indexOf("create trigger"),
    );
    expect(written).toContain(
      "better_supabase.broadcast_topic('organization:{organizationId=organization_id}:quotes', 'quote.changed');",
    );

    await sql(["sync"], {
      realtime: {
        policies,
        triggers: [
          {
            ...triggers[0]!,
            events: ["update"],
            when: { changed: ["status"] },
          },
        ],
      },
      blocks: ["realtime-tables"],
    });
    expect(await readFile(join(root, output), "utf-8")).toContain(
      `for each row when (old."status" is distinct from new."status") execute function better_supabase.broadcast_topic(`,
    );
    await expect(
      sql(["sync"], { realtime: { policies, triggers } }),
    ).rejects.toThrow("add realtime-tables to blocks");
    await expect(
      sql(["sync"], { realtime: { triggers }, blocks: ["realtime-tables"] }),
    ).rejects.toThrow("realtime.triggers needs realtime.policies");
    await expect(
      sql(["sync"], {
        realtime: {
          policies,
          triggers: [{ topic: "board:{boardId}", table: "cards" }],
        },
        blocks: ["realtime-tables"],
      }),
    ).rejects.toThrow(
      'realtime.triggers: no topic "board:{boardId}" in topics.ts',
    );
  });

  it("writes lookups, custom payloads and extra topics of realtime.triggers as topic.trigger() does", async () => {
    const realtime = resolve(
      import.meta.dirname,
      "../../../src/realtime/index.ts",
    );

    await writeFile(
      join(root, "topics.ts"),
      `import { defineTopic } from ${JSON.stringify(realtime)};
export const inbox = defineTopic("organization:{organizationId}:inbox");
export const thread = defineTopic("thread:{threadId}");
`,
    );
    const { defineTopic } = await import(realtime);
    const output = "supabase/schemas/905_topics.sql";
    const policies = { from: ["topics.ts"], output };

    const options = {
      values: {
        organizationId: {
          from: "public.threads",
          via: "thread_id",
          select: "organization_id",
        },
      },
      event: { insert: "created", update: "updated", delete: "deleted" },
      payload: {
        operation: { sql: "lower(tg_op)" },
        thread_id: "thread_id",
        record_id: "id",
      },
      functionSchema: "private",
    } as const;

    await sql(["sync"], {
      realtime: {
        policies,
        triggers: [
          {
            topic: "organization:{organizationId}:inbox",
            table: "public.messages",
            ...options,
            topics: [{ topic: "thread:{threadId}" }],
          },
        ],
      },
    });
    const written = await readFile(join(root, output), "utf-8");

    const expected = defineTopic("organization:{organizationId}:inbox").trigger(
      "public.messages",
      { ...options, topics: [{ topic: defineTopic("thread:{threadId}") }] },
    );

    expect(written).toContain(expected);
    expect(written).toContain(
      `vals := jsonb_build_object('organizationId', (lk_0."organization_id")::text);`,
    );
    expect(written).toContain(
      `vals := jsonb_build_object('threadId', (rec."thread_id")::text);`,
    );
    expect(written).toContain(
      "jsonb_build_object('operation', (lower(tg_op)), 'thread_id', rec.\"thread_id\", 'record_id', rec.\"id\")",
    );
    expect(written).toContain(
      "case tg_op when 'INSERT' then 'created' when 'UPDATE' then 'updated' when 'DELETE' then 'deleted' else tg_op end",
    );
    await expect(
      sql(["sync"], {
        realtime: {
          policies,
          triggers: [
            {
              topic: "thread:{threadId}",
              table: "messages",
              topics: [{ topic: "board:{boardId}" }],
            },
          ],
        },
      }),
    ).rejects.toThrow(
      'realtime.triggers[0].topics: no topic "board:{boardId}" in topics.ts',
    );
    await expect(
      sql(["sync"], {
        realtime: {
          policies,
          triggers: [
            {
              topic: "thread:{threadId}",
              table: "messages",
              values: { boardId: "board_id" },
              payload: { id: "id" },
            },
          ],
        },
      }),
    ).rejects.toThrow(
      'realtime.triggers[0]: defineTopic(thread:{threadId}).trigger: "boardId" is not a placeholder of thread:{threadId}',
    );
  });

  it("skips the topics whose receive policy a module writes", async () => {
    const realtime = resolve(
      import.meta.dirname,
      "../../../src/realtime/index.ts",
    );

    await writeFile(
      join(root, "topics.ts"),
      `import { defineTopic } from ${JSON.stringify(realtime)};
export const inbox = defineTopic("notifications:{userId}");
export const rows = defineTopic("bs:t:public.notes:{organizationId}");
export const chat = defineTopic("notifications:{user}:chat");
`,
    );
    await writeFile(
      join(root, "send.ts"),
      `import { defineTopic } from ${JSON.stringify(realtime)};
export const typing = defineTopic("bs:t:{room}", { send: true });
`,
    );
    const output = "supabase/schemas/905_topics.sql";
    const policies = { from: ["topics.ts", "send.ts"], output };
    await sql(["sync"], { realtime: { policies } });
    const alone = await readFile(join(root, output), "utf-8");
    expect(alone).toContain("-- better-supabase: topic notifications:{userId}");
    expect(alone).not.toContain("Skipped");

    const config: BetterSupabaseConfig = {
      realtime: { policies },
      blocks: ["notifications", "realtime-tables"],
    };

    await sql(["sync"], config);
    const written = await readFile(join(root, output), "utf-8");
    expect(written).toContain(
      "-- Skipped topic bs:t:public.notes:{organizationId}: the realtime-tables module writes its receive policy.\n-- Skipped topic notifications:{userId}: the notifications module writes its receive policy.\n",
    );
    expect(written).not.toContain(
      "-- better-supabase: topic notifications:{userId}",
    );
    expect(written).toContain(
      "-- better-supabase: topic notifications:{user}:chat",
    );
    expect(written).toContain("-- better-supabase: topic bs:t:{room}");
    expect(written).toContain("for insert to authenticated");
    expect((await sql(["sync", "--check"], config)).code).toBe(0);

    const off: BetterSupabaseConfig = {
      realtime: { policies },
      blocks: { notifications: { options: { realtime: "none" } } },
    };

    await sql(["sync"], off);
    expect(await readFile(join(root, output), "utf-8")).toContain(
      "-- better-supabase: topic notifications:{userId}",
    );
  });

  it("writes vector search in the schema the app installed pgvector in", async () => {
    await mkdir(join(root, "supabase/migrations"), { recursive: true });
    await writeFile(
      join(root, "supabase/migrations/20200101000000_init.sql"),
      "create extension if not exists vector with schema public;\n",
    );

    const config: BetterSupabaseConfig = {
      blocks: ["vector-search"],
      vectorSearch: { chunks: "embedding" },
    };

    expect((await sql(["sync"], config)).output).not.toContain(
      "_better_supabase_extensions.sql",
    );

    const file = await readFile(
      join(root, "supabase/schemas/900_better_supabase_18_vector_search.sql"),
      "utf-8",
    );

    expect(file).toContain(
      "create extension if not exists vector with schema public;",
    );
    expect(file).toContain("query public.vector, k integer default 10");
    expect((await sql(["sync"], config)).output).toContain("Unchanged");
  });

  it("has nothing to sync for an empty blocks", async () => {
    expect(await sql(["sync"])).toEqual({
      code: 0,
      data: { blocks: [] },
      output: "blocks is empty; nothing to sync.",
    });
  });

  it("writes appTables without any block, and removes the file after", async () => {
    const path = join(
      root,
      "supabase/schemas/900_better_supabase_app_tables.sql",
    );

    const config: BetterSupabaseConfig = {
      sql: { scope: "user" },
      appTables: { notes: { columns: { body: { type: "text" } } } },
    };

    expect((await sql(["sync"], config)).code).toBe(0);
    expect(await readFile(path, "utf-8")).toContain(
      'create table if not exists "public"."notes"',
    );
    expect(
      await readFile(
        join(root, "supabase/tests/900_better_supabase_app_tables.test.sql"),
        "utf-8",
      ),
    ).toContain("-- @bs-module-test app-tables");
    expect((await sql(["sync"], config)).output).toContain("Unchanged");

    await sql(["sync"], { blocks: ["updated-at"] });

    await expect(readFile(path, "utf-8")).rejects.toThrow("ENOENT");
  });

  it("writes the rows a schema diff skips into a data migration", async () => {
    expect(await sql(["data"])).toEqual({
      code: 0,
      data: { wrote: false },
      output: "blocks is empty; nothing to write.",
    });

    const config: BetterSupabaseConfig = { blocks: ["tenant", "rate-limit"] };

    const synced = await sql(["sync"], config);
    expect(synced.output).toContain(
      "Created supabase/better-supabase-data/900_better_supabase_04_tenant.sql (tenant)",
    );
    expect(synced.output).toContain("run `better-supabase sql data`");
    expect((await sql(["sync"], config)).output).not.toContain("sql data");

    expect((await sql(["data", "--dry-run"], config)).output).toMatch(
      /^Would create supabase\/migrations\/\d{14}_better_supabase_module_data\.sql$/,
    );
    const wrote = await sql(["data"], config);
    const path = wrote.output!.replace("Created ", "");
    expect(path).toMatch(
      /^supabase\/migrations\/\d{14}_better_supabase_module_data\.sql$/,
    );
    const migration = await readFile(join(root, path), "utf-8");
    expect(migration).toContain("values ('tenant', 2, 'managed')");
    expect(migration).toContain("values ('rate-limit',");
    expect(migration).toContain(
      "alter role authenticator set pgrst.db_pre_request",
    );
    expect(migration).not.toContain("create table");
    expect(await sql(["data"], config)).toEqual({
      code: 0,
      data: { file: path, wrote: false },
      output: `${path} already has these rows; nothing to write.`,
    });
  });

  it("writes a pgTAP file per audited table and removes the ones it no longer writes", async () => {
    const config: BetterSupabaseConfig = { blocks: ["audit"] };
    const schemas = join(root, "supabase/schemas");
    const migrations = join(root, "supabase/migrations");
    await mkdir(schemas, { recursive: true });
    await mkdir(migrations, { recursive: true });
    await writeFile(
      join(schemas, "010_crm.sql"),
      "select better_supabase.audit('public.customers', ignore => '{updated_at}');\nselect better_supabase.audit('public.notes');\n",
    );
    await writeFile(
      join(migrations, "20260101000000_unaudit.sql"),
      "select better_supabase.unaudit('public.notes');\n",
    );

    const test =
      "supabase/tests/900_better_supabase_audit_public_customers.test.sql";

    const synced = await sql(["sync"], config);
    expect(synced.output).toContain(`Created ${test} (audit)`);
    expect(synced.output).not.toContain("public_notes");
    expect(await readFile(join(root, test), "utf-8")).toContain(
      `'{"updated_at"}'::text[]`,
    );
    expect(await sql(["sync", "--check"], config)).toMatchObject({ code: 0 });

    await writeFile(join(schemas, "010_crm.sql"), "");
    const check = await sql(["sync", "--check"], config);
    expect(check).toMatchObject({ code: 1 });
    expect(check.error).toContain(test);
    expect((await sql(["sync", "--dry-run"], config)).output).toContain(
      `Would remove ${test}`,
    );
    expect((await sql(["sync"], config)).output).toContain(`Removed ${test}`);
    expect(await sql(["sync", "--check"], config)).toMatchObject({ code: 0 });
  });

  it("removes a dropped table's pgTAP file", async () => {
    const config: BetterSupabaseConfig = { blocks: ["audit"] };
    const migrations = join(root, "supabase/migrations");
    await mkdir(migrations, { recursive: true });
    await writeFile(
      join(migrations, "20260101000000_crm.sql"),
      "create table public.notes (id int primary key);\nselect better_supabase.audit('public.notes');\n",
    );

    const test =
      "supabase/tests/900_better_supabase_audit_public_notes.test.sql";

    expect((await sql(["sync"], config)).output).toContain(
      `Created ${test} (audit)`,
    );
    await writeFile(
      join(migrations, "20260201000000_drop_notes.sql"),
      "drop table if exists public.notes;\n",
    );
    expect((await sql(["sync"], config)).output).toContain(`Removed ${test}`);
    expect(await sql(["sync", "--check"], config)).toMatchObject({ code: 0 });
  });

  it("leaves the generated pgTAP files out of sql upgrade --check", async () => {
    const config: BetterSupabaseConfig = { blocks: ["audit", "pgtap"] };

    await mkdir(join(root, "supabase/schemas"), { recursive: true });
    await writeFile(
      join(root, "supabase/schemas/010_crm.sql"),
      "select better_supabase.audit('public.customers');\n",
    );
    expect((await sql(["sync"], config)).output).toContain(
      "supabase/tests/900_better_supabase_audit_public_customers.test.sql (audit)",
    );
    expect(await sql(["upgrade", "--check"], config)).toEqual({
      code: 0,
      data: { upgrades: [], stale: [] },
      output: "SQL modules are at their current versions.",
    });
  });

  it("derives grants from the schema files' policies with fromPolicies", async () => {
    const config: BetterSupabaseConfig = {
      expose: { notes: ["select"] },
      blocks: { grants: { options: { fromPolicies: true } } },
    };

    const schemas = join(root, "supabase/schemas");
    await mkdir(schemas, { recursive: true });
    await writeFile(
      join(schemas, "010_crm.sql"),
      "create policy notes_all on public.notes for all to authenticated using (true);\ncreate policy tags_read on public.tags for select to anon, authenticated using (true);\n",
    );
    await sql(["sync"], config);

    const file = await readFile(
      join(root, "supabase/schemas/900_better_supabase_13_grants.sql"),
      "utf-8",
    );

    expect(file).toContain(
      'grant select on table "public"."notes" to authenticated;',
    );
    expect(file).toContain(
      'grant select on table "public"."tags" to anon;\ngrant select on table "public"."tags" to authenticated;',
    );
  });

  it("revokes declared tables that no policy or expose entry reaches with fromPolicies", async () => {
    const schemas = join(root, "supabase/schemas");
    await mkdir(schemas, { recursive: true });
    await writeFile(
      join(schemas, "010_notes.sql"),
      'create table public.notes (id int);\ncreate table public.jobs (id int);\ncreate table public.tags (id int);\ncreate table public.open (id int);\ncreate table public.later (id int);\nalter table public.jobs enable row level security;\nalter table only "public"."later" enable row level security;\nalter table public.later disable row level security;\ncreate policy notes_read on public.notes for select to authenticated using (true);\n',
    );
    await sql(["sync"], {
      expose: { tags: ["select"] },
      blocks: { grants: { options: { fromPolicies: true } } },
    });

    const file = await readFile(
      join(schemas, "900_better_supabase_13_grants.sql"),
      "utf-8",
    );

    expect(file).toContain(
      [
        'revoke all on table "public"."jobs" from public, anon, authenticated, service_role;',
        'grant select, insert, update, delete on table "public"."jobs" to service_role;',
      ].join("\n"),
    );
    expect(file).toContain(
      'grant select on table "public"."notes" to authenticated;',
    );
    expect(file).toContain(
      'grant select on table "public"."tags" to authenticated;',
    );
    expect(file).not.toContain(
      'grant select, insert, update, delete on table "public"."tags" to authenticated',
    );
  });

  it("reads policies and tables from the declarative schema, not old migrations", async () => {
    await mkdir(join(root, "supabase/schemas"), { recursive: true });
    await mkdir(join(root, "supabase/migrations"), { recursive: true });
    await writeFile(
      join(root, "supabase/config.toml"),
      "[experimental.pgdelta]\nenabled = true\n",
    );
    await writeFile(
      join(root, "supabase/migrations/20200101000000_init.sql"),
      "create table public.legacy (id int);\ncreate policy legacy_all on public.legacy for all to authenticated using (true);\n",
    );
    await writeFile(
      join(root, "supabase/schemas/010_notes.sql"),
      "create table public.notes (id int);\ncreate policy notes_read on public.notes for select to authenticated using (true);\n",
    );
    await sql(["sync"], {
      blocks: {
        grants: { options: { fromPolicies: true } },
        sessions: { options: { policies: true } },
      },
    });

    const grants = await readFile(
      join(root, "supabase/schemas/900_better_supabase_13_grants.sql"),
      "utf-8",
    );

    expect(grants).toContain(
      'grant select on table "public"."notes" to authenticated;',
    );
    expect(grants).not.toContain("legacy");

    const sessions = await readFile(
      join(root, "supabase/schemas/900_better_supabase_26_sessions.sql"),
      "utf-8",
    );

    expect(sessions).toContain('on "public"."notes"');
    expect(sessions).not.toContain("legacy");
  });

  it("grants column privileges from expose", async () => {
    await sql(["sync"], {
      expose: {
        "public.posts": {
          anon: ["select(id, title)"],
          authenticated: ["select", "update(title, body)"],
        },
      },
      blocks: ["grants"],
    });

    const file = await readFile(
      join(root, "supabase/schemas/900_better_supabase_13_grants.sql"),
      "utf-8",
    );

    expect(file).toContain(
      'grant select ("id", "title") on table "public"."posts" to anon;',
    );
    expect(file).toContain(
      'grant select, update ("title", "body") on table "public"."posts" to authenticated;',
    );
    expect(() =>
      resolveConfig({ expose: { posts: ["delete(id)" as "delete"] } }, root),
    ).toThrow(/is not a privilege/);
  });

  it("resolves expose exclusions against the declared columns", async () => {
    const schemas = join(root, "supabase/schemas");
    await mkdir(schemas, { recursive: true });
    await writeFile(
      join(schemas, "010_keys.sql"),
      'create table public.api_keys (\n  id uuid primary key,\n  name text not null,\n  "token_hash" text,\n  secret text,\n  unique (name)\n);\n',
    );
    await sql(["sync"], {
      expose: {
        api_keys: {
          authenticated: ["select(*, -token_hash, -secret)", "update(name)"],
        },
      },
      blocks: ["grants"],
    });

    const file = await readFile(
      join(schemas, "900_better_supabase_13_grants.sql"),
      "utf-8",
    );

    expect(file).toContain(
      'grant select ("id", "name"), update ("name") on table "public"."api_keys" to authenticated;',
    );

    await expect(
      sql(["sync"], {
        expose: { notes: ["select(*, -body)"] },
        blocks: ["grants"],
      }),
    ).rejects.toThrow(
      "no `create table` in the schema files declares public.notes",
    );
    expect(() =>
      resolveConfig({ expose: { notes: ["select(*, body)"] } }, root),
    ).toThrow(/is not a privilege/);
  });

  it("derives sameTenant triggers from the declared foreign keys", async () => {
    const schemas = join(root, "supabase/schemas");
    await mkdir(schemas, { recursive: true });
    await writeFile(
      join(schemas, "010_crm.sql"),
      "create table public.customers (id uuid primary key, organization_id uuid not null);\ncreate table public.tasks (id uuid primary key, organization_id uuid not null, customer_id uuid references public.customers);\n",
    );
    await sql(["sync"], {
      blocks: { tenant: { options: { sameTenant: { auto: true } } } },
    });

    const names = await readdir(schemas);

    const tenant = await readFile(
      join(
        schemas,
        names.find((name) => name.endsWith("_tenant.sql"))!,
      ),
      "utf-8",
    );

    expect(tenant).toContain(
      `create trigger "bs_same_tenant_customer_id" before insert or update of "customer_id", "organization_id" on "public"."tasks"`,
    );
  });

  it("writes the session policy on the tables the schema files create", async () => {
    const schemas = join(root, "supabase/schemas");
    await mkdir(schemas, { recursive: true });
    await writeFile(
      join(schemas, "010_crm.sql"),
      "create table public.notes (id int);\ncreate table public.audit_log (id int);\n",
    );
    await sql(["sync"], {
      blocks: {
        sessions: { options: { policies: true, exclude: ["public.audit_*"] } },
      },
    });

    const file = await readFile(
      join(root, "supabase/schemas/900_better_supabase_26_sessions.sql"),
      "utf-8",
    );

    expect(file).toContain(
      'create policy bs_session_active on "public"."notes"',
    );
    expect(file).not.toContain("audit_log");
  });

  it("keeps data files out of pg-delta's schema folder when sql.dir is inside it", async () => {
    await mkdir(join(root, "supabase"), { recursive: true });
    await writeFile(
      join(root, "supabase/config.toml"),
      '[experimental.pgdelta]\nenabled = true\ndeclarative_schema_path = "./declarative"\n',
    );

    const synced = await sql(["sync"], {
      sql: { dir: "supabase/declarative/module" },
      blocks: ["tenant"],
    });

    expect(synced.output).toContain(
      "Created supabase/declarative/module/900_better_supabase_04_tenant.sql (tenant)",
    );
    expect(synced.output).toContain(
      "Created supabase/better-supabase-data/900_better_supabase_04_tenant.sql (tenant)",
    );
  });

  it("writes the module extensions into a migration before the schema migration", async () => {
    const config: BetterSupabaseConfig = { blocks: ["jobs", "jsonb-schemas"] };

    await mkdir(join(root, "supabase/migrations"), { recursive: true });
    await writeFile(
      join(root, "supabase/migrations/20200101000000_init.sql"),
      "create extension if not exists pgmq;\n",
    );
    expect((await sql(["sync", "--dry-run"], config)).output).toMatch(
      /^Would create supabase\/migrations\/\d{14}_better_supabase_extensions\.sql$/m,
    );
    const synced = await sql(["sync"], config);

    const path =
      /^Created (supabase\/migrations\/\d{14}_better_supabase_extensions\.sql)$/m.exec(
        synced.output ?? "",
      )?.[1];

    expect(path).toBeDefined();
    expect(synced.output).toContain("create the schema migration after it");
    expect(await readFile(join(root, path!), "utf-8")).toBe(
      '-- better-supabase sql: the extensions of pg_jsonschema, created before the schema migration that needs them.\n\ncreate extension if not exists "pg_jsonschema" with schema "extensions";\n',
    );
    expect((await sql(["sync"], config)).output).not.toContain(
      "_better_supabase_extensions.sql",
    );
    expect((await sql(["data"], config)).output).toMatch(
      /^Created supabase\/migrations\/\d{14}_better_supabase_module_data\.sql$/,
    );
  });

  it("refuses a data migration while no earlier migration creates a module extension", async () => {
    const config: BetterSupabaseConfig = { blocks: ["jsonb-schemas"] };

    await sql(["sync"], config);
    const migrations = join(root, "supabase/migrations");

    const written = (await readdir(migrations)).find((name) =>
      name.endsWith("_better_supabase_extensions.sql"),
    );

    await rm(join(migrations, written!));
    await writeFile(
      join(migrations, "20200101000000_better_supabase_module_data.sql"),
      'create extension if not exists "pg_jsonschema" with schema "extensions";\n',
    );
    expect(await sql(["data"], config)).toEqual({
      code: 1,
      error:
        "No migration before the data migration creates pg_jsonschema, and the schema migration needs it while it applies.\nRun `better-supabase sql sync` to write the extensions migration, then create the schema migration again after it.",
    });
    await writeFile(
      join(migrations, "20200101000001_extensions.sql"),
      'CREATE EXTENSION "pg_jsonschema" WITH SCHEMA extensions;\n',
    );
    expect((await sql(["data"], config)).code).toBe(0);
  });

  it("stamps the data migration after the newest migration", async () => {
    const config: BetterSupabaseConfig = { blocks: ["tenant"] };
    await sql(["sync"], config);
    await mkdir(join(root, "supabase/migrations"), { recursive: true });
    await writeFile(
      join(root, "supabase/migrations/29991231235959_block.sql"),
      "",
    );
    expect((await sql(["data"], config)).output).toBe(
      "Created supabase/migrations/30000101000000_better_supabase_module_data.sql",
    );
  });

  it("never reuses a timestamp another tool's migration took", async () => {
    const config: BetterSupabaseConfig = { blocks: ["tenant"] };
    await sql(["sync"], config);
    await mkdir(join(root, "supabase/migrations"), { recursive: true });
    await writeFile(
      join(root, "supabase/migrations/39991231235959-authz_seeds.sql"),
      "",
    );
    await writeFile(join(root, "supabase/migrations/40000101000000.sql"), "");
    expect((await sql(["data"], config)).output).toBe(
      "Created supabase/migrations/40000101000001_better_supabase_module_data.sql",
    );
  });

  it("puts migrations next to the config.toml above sql.dir", async () => {
    await mkdir(join(root, "db/supabase/schemas"), { recursive: true });
    await writeFile(join(root, "db/supabase/config.toml"), "");
    const config = resolveConfig({ sql: { dir: "db/supabase/schemas" } }, root);
    expect(migrationsDir(config)).toBe("db/supabase/migrations");
    expect(migrationsDir(resolveConfig({}, root))).toBe("supabase/migrations");
  });

  it("finds a shared stack's migrations when sql.dir is outside the project", async () => {
    const app = join(root, "apps/web");
    await mkdir(app, { recursive: true });
    await mkdir(join(root, "stack/supabase/schemas"), { recursive: true });
    await writeFile(join(root, "stack/supabase/config.toml"), "");

    const config = resolveConfig(
      { sql: { dir: "../../stack/supabase/schemas" } },
      app,
    );

    expect(migrationsDir(config)).toBe("../../stack/supabase/migrations");
  });

  it("syncs and checks modules in a shared stack outside the project", async () => {
    const app = join(root, "apps/web");
    await mkdir(app, { recursive: true });
    await mkdir(join(root, "stack/supabase/schemas"), { recursive: true });
    await writeFile(join(root, "stack/supabase/config.toml"), "");

    const config = resolveConfig(
      { blocks: ["tenant"], sql: { dir: "../../stack/supabase/schemas" } },
      app,
    );

    const synced = await runSql(config, parseArgs(["sync"], SQL_ARGS));
    expect(synced.code).toBe(0);
    expect(synced.output).toContain("../../stack/supabase/schemas/");

    const checked = await runSql(
      config,
      parseArgs(["sync", "--check"], SQL_ARGS),
    );

    expect(checked.code).toBe(0);
  });

  it("upgrades modules installed before versioned headers", async () => {
    const config: BetterSupabaseConfig = { blocks: ["tenant"] };
    expect(await sql(["upgrade"])).toEqual({
      code: 0,
      data: { upgrades: [], stale: [] },
      output: "blocks is empty; nothing to upgrade.",
    });
    expect(await sql(["upgrade", "--check"], config)).toEqual({
      code: 0,
      data: { upgrades: [], stale: [] },
      output: "SQL modules are at their current versions.",
    });
    await sql(["sync"], config);

    const file = renderModules(
      ["tenant"],
      moduleLayout(resolveConfig(config, root)),
    ).find((module) => module.module === "tenant" && module.kind === "schema");

    const path = join(root, file!.path);

    const legacy = (await readFile(path, "utf-8")).replace(
      /^-- @bs-module .*\n/m,
      "",
    );

    await writeFile(path, legacy);

    const check = await sql(["upgrade", "--check"], config);
    expect(check.code).toBe(1);
    expect(check.error).toContain(
      "tenant is at version 1; the current version is 2",
    );
    expect(check.error).toContain("Run `better-supabase sql upgrade`.");

    const dry = await sql(["upgrade", "--dry-run"], config);
    expect(dry.output).toContain("tenant: version 1 to 2");
    expect(await readFile(path, "utf-8")).toBe(legacy);

    const done = await sql(["upgrade"], config);
    expect(done.output).toContain(
      "Renames memberships.org_id to organization_id",
    );
    expect(done.next?.[0]?.when).toBe(
      "creates a migration from the module files",
    );
    expect(await readFile(path, "utf-8")).toContain("-- @bs-module tenant@2");
    expect((await sql(["upgrade"], config)).output).toBe(
      "SQL modules are at their current versions.",
    );
  });

  it("reports a stale file at the current version in upgrade --check", async () => {
    const config: BetterSupabaseConfig = { blocks: ["mfa"] };
    await sql(["sync"], config);

    const [file] = renderModules(
      ["mfa"],
      moduleLayout(resolveConfig(config, root)),
    );

    await writeFile(
      join(root, file!.path),
      `${await readFile(join(root, file!.path), "utf-8")}\n-- edited\n`,
    );
    const check = await sql(["upgrade", "--check"], config);
    expect(check.code).toBe(1);
    expect(check.error).toMatch(/^Out of date: .*mfa\.sql\./);
    expect(check.output).toContain("-- edited");
  });

  it("turns pg-delta on under the pg-delta workflow, and leaves migra alone", async () => {
    await mkdir(join(root, "supabase"), { recursive: true });
    await writeFile(
      join(root, "supabase/config.toml"),
      "[api]\nport = 54321\n",
    );
    const config: BetterSupabaseConfig = { blocks: ["mfa"] };

    const migra = await sql(["sync"], {
      sql: { ...config.sql, workflow: "migra" },
    });

    expect(migra.output).not.toContain("pg-delta");
    await rm(join(root, "supabase/schemas"), { recursive: true, force: true });
    const synced = await sql(["sync"], config);
    expect(synced.output).toContain("Enabled pg-delta in supabase/config.toml");
    expect(await readFile(join(root, "supabase/config.toml"), "utf-8")).toBe(
      "[api]\nport = 54321\n\n[experimental.pgdelta]\nenabled = true\n",
    );
    expect((await sql(["sync"], config)).output).not.toContain("pg-delta");
  });

  describe("the migrations workflow", () => {
    const migrations = (blocks: string[]): BetterSupabaseConfig => ({
      sql: { workflow: "migrations" },
      blocks,
    });

    const moduleMigrations = async (): Promise<string[]> =>
      (await readdir(join(root, "supabase/migrations")).catch(() => []))
        .filter((name) => name.endsWith("_better_supabase_modules.sql"))
        .toSorted();

    it("writes the modules into one migration and nothing into sql.dir", async () => {
      const config = migrations(["jobs", "jsonb-schemas"]);
      expect((await sql(["sync", "--dry-run"], config)).output).toMatch(
        /^Would create supabase\/migrations\/\d{14}_better_supabase_modules\.sql$/m,
      );
      const synced = await sql(["sync"], config);
      expect(synced.output).toMatch(
        /^Created supabase\/migrations\/\d{14}_better_supabase_modules\.sql$/m,
      );
      expect(synced.output).not.toContain("sql data");
      expect(
        await readdir(join(root, "supabase/schemas")).catch(() => []),
      ).toEqual([]);
      const [name] = await moduleMigrations();

      const text = await readFile(
        join(root, "supabase/migrations", name!),
        "utf-8",
      );

      expect(text).toMatch(/^-- better-supabase sql: the SQL modules /);
      expect(text).toContain("-- @bs-module jobs@");
      expect(text).toContain("-- @bs-module jsonb-schemas@");
      expect(
        text.indexOf('create extension if not exists "pg_jsonschema"'),
      ).toBeLessThan(text.indexOf("-- @bs-module jobs@"));

      expect((await sql(["sync"], config)).output).toContain(
        `Unchanged supabase/migrations/${name!} (it has these statements)`,
      );
      expect(await moduleMigrations()).toHaveLength(1);
      expect(await sql(["sync", "--check"], config)).toEqual({
        code: 0,
        data: { stale: [] },
        output: "SQL module migration is up to date.",
      });

      const more = migrations(["jobs", "jsonb-schemas", "mfa"]);
      const check = await sql(["sync", "--check"], more);
      expect(check.code).toBe(1);
      expect(check.error).toBe(
        `Out of date: supabase/migrations/${name!}. Run \`better-supabase sql sync\`, then \`supabase migration up\`.`,
      );
      await sql(["sync"], more);
      expect(await moduleMigrations()).toHaveLength(2);
      expect((await sql(["sync", "--check"], more)).code).toBe(0);
    });

    it("keeps the pgTAP files in sql.testsDir and checks them", async () => {
      const config = migrations(["pgtap"]);
      await sql(["sync"], config);

      const tests = await readdir(join(root, "supabase/tests"), {
        recursive: true,
      });

      const file = tests.find((name) => name.endsWith(".sql"));
      expect(file).toBeDefined();
      expect((await sql(["sync", "--check"], config)).code).toBe(0);
      await writeFile(join(root, "supabase/tests", file!), "-- edited\n");
      const check = await sql(["sync", "--check"], config);
      expect(check.code).toBe(1);
      expect(check.error).toContain(`supabase/tests/${file!}`);
    });

    it("upgrades nothing before the first module migration", async () => {
      expect(await sql(["upgrade", "--check"], migrations(["mfa"]))).toEqual({
        code: 0,
        data: { upgrades: [], stale: [] },
        output: "SQL modules are at their current versions.",
      });
    });

    it("reports a missing module migration in sync --check", async () => {
      const check = await sql(["sync", "--check"], migrations(["mfa"]));
      expect(check.code).toBe(1);
      expect(check.error).toContain(
        "supabase/migrations/<stamp>_better_supabase_modules.sql",
      );
    });

    it("adds a module into the migration and says to apply it", async () => {
      const added = await sql(["add", "mfa"], migrations([]));
      expect(added.output).toMatch(
        /^Created supabase\/migrations\/\d{14}_better_supabase_modules\.sql$/m,
      );
      expect(added.next).toEqual([
        { command: "supabase migration up", when: "applies the migration" },
      ]);
    });

    it("keeps the rows in the module migration, so sql data writes nothing", async () => {
      const config = migrations(["tenant"]);
      await sql(["sync"], config);
      const [name] = await moduleMigrations();

      const text = await readFile(
        join(root, "supabase/migrations", name!),
        "utf-8",
      );

      expect(text).toContain("-- @bs-module-data tenant");
      expect((await sql(["data"], config)).output).toContain(
        "already writes the rows into the module migration; nothing to write.",
      );
    });

    it("lists the modules the newest migration installs", async () => {
      const config = migrations(["mfa"]);
      expect((await sql(["list"], config)).output).not.toMatch(/^● mfa/m);
      await sql(["sync"], config);
      expect((await sql(["list"], config)).output).toMatch(/^● mfa/m);
    });

    it("reads installed versions from the migration and writes the upgrade steps into the next one", async () => {
      const config = migrations(["tenant"]);
      await sql(["sync"], config);
      const [name] = await moduleMigrations();
      const path = join(root, "supabase/migrations", name!);
      await writeFile(
        path,
        (await readFile(path, "utf-8")).replace(
          /^-- @bs-module tenant@2/m,
          "-- @bs-module tenant@1",
        ),
      );
      const check = await sql(["upgrade", "--check"], config);
      expect(check.code).toBe(1);
      expect(check.error).toContain(
        "tenant is at version 1; the current version is 2",
      );
      const done = await sql(["upgrade"], config);
      expect(done.output).toContain(
        "Renames memberships.org_id to organization_id",
      );
      expect(done.next).toEqual([
        { command: "supabase migration up", when: "applies the migration" },
      ]);
      expect(done.output).not.toContain("_better_supabase_block_upgrade.sql");
      const all = await moduleMigrations();
      expect(all).toHaveLength(2);

      const upgraded = await readFile(
        join(root, "supabase/migrations", all[1]!),
        "utf-8",
      );

      expect(upgraded).toContain("-- @bs-upgrade-start");
      expect(upgraded.indexOf("-- @bs-upgrade-end")).toBeLessThan(
        upgraded.indexOf("-- @bs-module tenant@2"),
      );
      expect((await sql(["upgrade"], config)).output).toBe(
        "SQL modules are at their current versions.",
      );
      expect((await sql(["sync"], config)).output).toContain("Unchanged ");
    });
  });

  it("prints a rendered module with the configured claims", async () => {
    const printed = await sql(["print", "tenant"], {
      claims: { scope: "workspace" },
    });

    expect(printed.code).toBe(0);
    expect(printed.output).toContain("'workspace'");
    expect(printed.output).not.toBe(SQL_MODULES["tenant"]!.sql);
    expect(await sql(["print", "mfa"])).toEqual({
      code: 0,
      data: { module: "mfa", custom: false, sql: SQL_MODULES["mfa"]!.sql },
      output: SQL_MODULES["mfa"]!.sql,
    });
  });

  it("prints the contract of a custom-mode module", async () => {
    const printed = await sql(["print", "tenant"], {
      blocks: { tenant: { mode: "custom", schema: "app" } },
    });

    expect(printed.code).toBe(0);
    expect(printed.output).toMatch(
      /^-- blocks\.tenant is in custom mode: the app writes these functions\.\n-- app\./,
    );
  });

  it("stops on an entitlements scope the provider lacks", async () => {
    const config = { authorization: withProvider({ tenantScope: "team" }) };
    await expect(sql(["print", "entitlements"], config)).rejects.toThrow(
      /tenantScope "team" is not a scope/,
    );
    expect(await sql(["list"], config)).toMatchObject({ code: 0 });
    expect(await sql(["print", "audit"], config)).toMatchObject({ code: 0 });
  });

  it("guards the tenant module when the provider's hook owns the memberships claim", async () => {
    expect(
      await sql(["add", "tenant"], { authorization: stubProvider }),
    ).toMatchObject({
      code: 1,
      error: expect.stringContaining(
        "The access token hook of the authorization provider (stub) writes the memberships claim.",
      ),
    });

    expect(
      await sql(["add", "tenant", "--allow-hook-overlap", "--dry-run"], {
        authorization: stubProvider,
      }),
    ).toMatchObject({ code: 0 });
  });

  describe("the provider access model", () => {
    const provider = (
      authorization:
        | BetterSupabaseConfig["authorization"]
        | null = stubProvider,
      extra: BetterSupabaseConfig = {},
    ): BetterSupabaseConfig => ({
      blocks: { access: { model: "provider" } },
      ...(authorization ? { authorization } : {}),
      ...extra,
    });

    const complete = withProvider({
      permissions: modulePermissionKeys(
        { access: { model: "provider" } },
        Object.keys(SQL_MODULES),
      ).map((entry) => ({ key: entry.key, sqlComplete: true })),
    });

    it("renders the provider's functions, whatever entitlements says", async () => {
      for (const config of [
        provider(complete),
        provider(complete, { entitlements: { memberships: "tenant" } }),
      ]) {
        const printed = await sql(["print", "access"], config);
        expect(printed.output).toContain("authz.ids_organization(");
      }
    });

    it("stops without an authorization provider", async () => {
      await expect(sql(["print", "access"], provider(null))).rejects.toThrow(
        /the config has no authorization/,
      );
      expect(await sql(["list"], provider(null))).toMatchObject({ code: 0 });
      expect(await sql(["print", "audit"], provider(null))).toMatchObject({
        code: 0,
      });
    });

    it("stops on a module permission key the provider doesn't mark sqlComplete", async () => {
      await expect(
        sql(
          ["add", "organizations", "--dry-run"],
          provider(
            withProvider({
              permissions: [{ key: "organization.update", sqlComplete: false }],
            }),
          ),
        ),
      ).rejects.toThrow(
        /checks "organization\.update" \(update\) with authorization\.functions\.idsWith, but it has conditions[\s\S]*"organization\.delete" \(delete\).*is not in authorization\.permissions/,
      );
    });
  });

  it("refuses to render entitlements for a scope id type it doesn't support", async () => {
    await expect(
      sql(["print", "entitlements"], {
        authorization: withProvider({
          scopes: [{ name: "organization", idType: "numeric" }],
        }),
      }),
    ).rejects.toThrow(/scope "organization" has idType "numeric"/);
  });
});
