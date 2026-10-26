import type { PoolClient } from "pg";

import { QueryClient } from "@tanstack/query-core";
import { Pool } from "pg";
import * as v from "valibot";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";

import type { SqlClient } from "../../src/postgres/executor.ts";

import { createAttachments } from "../../src/blocks/attachments/attachments.ts";
import { defineBlocks } from "../../src/blocks/create-blocks.ts";
import { outboxBlock } from "../../src/blocks/outbox/manifest.ts";
import { renameBlock } from "../../src/blocks/rename-block.ts";
import { tasksBlock } from "../../src/blocks/tasks/manifest.ts";
import { blockConfigEntries } from "../../src/cli/gen/blocks.ts";
import { resolveConfig } from "../../src/config/resolve.ts";
import { emitBlockEvent } from "../../src/core/block-events.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { EventHub } from "../../src/core/events.ts";
import { createNext } from "../../src/next/index.ts";
import {
  blockQueries,
  invalidateOnBlockEvents,
} from "../../src/query/blocks.ts";
import { renderBlocks } from "../../src/sql/render.ts";
import { createTestSigner } from "../../src/testing/jwt.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { stackDbUrl } from "./stack-env.ts";

const mocks = vi.hoisted(() => ({ headers: new Headers() }));

vi.mock(import("next/headers.js"), () => ({
  headers: () => Promise.resolve(mocks.headers),
  cookies: () =>
    Promise.resolve(
      // SAFETY: a bearer-token action only awaits the jar and never reads it.
      {
        set: () => undefined,
        getAll: () =>
          (mocks.headers.get("cookie") ?? "")
            .split("; ")
            .filter(Boolean)
            .map((pair) => ({
              name: pair.slice(0, pair.indexOf("=")),
              value: decodeURIComponent(pair.slice(pair.indexOf("=") + 1)),
            })),
      } as never,
    ),
}));

vi.mock(import("next/cache.js"), () => ({
  updateTag: () => undefined,
  revalidateTag: () => undefined,
  cacheTag: () => undefined,
  cacheLife: () => undefined,
  io: () => Promise.resolve(),
}));

/**
 * A scratch schema for every module, since the stack's shared tables already
 * carry the default tenant column.
 */
const SCRATCH = "bsb_entity_rename";

const TENANT = "5f3c6a52-8d1e-4b7a-9c0f-2a4b6c8d0e1f";

async function reachable(): Promise<boolean> {
  const url = process.env["SUPABASE_DB_URL"];

  if (url === undefined) {
    return false;
  }

  const pool = new Pool({
    connectionString: url,
    connectionTimeoutMillis: 5000,
  });

  try {
    await pool.query("select 1");

    return true;
  } catch {
    return false;
  } finally {
    await pool.end();
  }
}

const live = await reachable();

const config = resolveConfig(
  {
    blocks: {
      "updated-at": { schema: SCRATCH },
      memberships: { schema: SCRATCH, names: { organization: "workspace" } },
      permissions: { schema: SCRATCH },
      subjects: { schema: SCRATCH },
      pipelines: { schema: SCRATCH },
      outbox: { schema: SCRATCH },
      tasks: { schema: SCRATCH, names: { work_item: "task" } },
      attachments: { schema: SCRATCH, options: { requireScan: false } },
    },
  },
  "/project",
);

const generated = blockConfigEntries(config);

/** The names `gen` writes for tasks, as `blocks.generated.ts` declares them. */
const NAMES = {
  tenant: "workspace",
  entities: [
    {
      from: { singular: "work_item", plural: "work_items" },
      to: { singular: "task", plural: "tasks" },
    },
  ],
} as const;

const blocks = defineBlocks(generated, {
  tasks: renameBlock(tasksBlock, NAMES),
  outbox: outboxBlock.with({ source: "https://app.test" }),
});

/**
 * The transaction's connection as a `SqlClient`; each statement runs in a
 * savepoint so a failed call leaves the transaction usable.
 */
function inTransaction(client: PoolClient): SqlClient {
  return {
    async queryRaw<T>(text: string, params?: unknown[]): Promise<T[]> {
      await client.query("savepoint call");

      try {
        const { rows } = await client.query(text, params);
        await client.query("release savepoint call");

        // SAFETY: the caller names the row shape its statement selects.
        return rows as T[];
      } catch (error) {
        await client.query("rollback to savepoint call");
        throw error;
      }
    },
  };
}

describe.skipIf(!live)("renamed entities against Postgres", () => {
  let pool: Pool;
  let client: PoolClient;
  let built: ReturnType<typeof blocks.create>;

  beforeAll(async () => {
    pool = new Pool({ connectionString: stackDbUrl(), max: 1 });
    client = await pool.connect();
    await client.query("begin");
    await client.query(`create schema ${SCRATCH}`);

    const files = renderBlocks(config.blockNames, {
      modules: config.blocks,
      subjects: config.subjects,
    });

    // attachment_subject_readable is SQL-language and names the `tasks` table,
    // which tasks creates after it.
    for (const file of [
      ...files.filter((file) => file.module !== "attachments"),
      ...files.filter((file) => file.module === "attachments"),
    ]) {
      if (file.kind !== "test") {
        await client.query(file.contents);
      }
    }

    await client.query(
      `select set_config('request.jwt.claims', '{"role": "service_role"}', true)`,
    );

    built = blocks.create({ transport: sqlTransport(inTransaction(client)) });
  });

  afterAll(async () => {
    await client.query("rollback");
    client.release();
    await pool.end();
  });

  it("generates the names the client is renamed with", () => {
    expect(generated["tasks"]?.names).toEqual(NAMES);
  });

  it("installs the renamed tables, functions and permission keys", async () => {
    const { rows: tables } = await client.query<{ name: string }>(
      `select table_name as name from information_schema.tables
       where table_schema = $1 and table_name in ('tasks', 'task_assignees')
       order by 1`,
      [SCRATCH],
    );

    const { rows: functions } = await client.query<{ name: string }>(
      `select distinct p.proname as name from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = $1
         and p.proname in ('create_task', 'update_tasks', 'list_tasks')
       order by 1`,
      [SCRATCH],
    );

    const { rows: columns } = await client.query<{ name: string }>(
      `select column_name as name from information_schema.columns
       where table_schema = $1 and table_name = 'outbox_events' and column_name ~ '_id$'
       order by 1`,
      [SCRATCH],
    );

    const { rows: permissions } = await client.query<{ key: string }>(
      `select better_supabase.operation_permission(op) as key
       from unnest(array['tasks.read', 'tasks.write', 'tasks.manage']) as op`,
    );

    expect({
      tables: tables.map((row) => row.name),
      functions: functions.map((row) => row.name),
      columns: columns.map((row) => row.name),
      permissions: permissions.map((row) => row.key),
    }).toEqual({
      tables: ["task_assignees", "tasks"],
      functions: ["create_task", "list_tasks", "update_tasks"],
      columns: ["actor_id", "workspace_id"],
      permissions: ["tasks.read", "tasks.write", "tasks.manage"],
    });
  });

  it("creates, lists and updates through the renamed client", async () => {
    const created = await built.tasks
      .create(TENANT, { title: "Ship" })
      .orThrow();

    const listed = await built.tasks.list(TENANT).orThrow();

    const changed = await built.tasks
      .update([{ taskId: created.id, field: "title", value: "Shipped" }])
      .orThrow();

    expect({
      title: created.title,
      listed: listed.map((task) => task.id),
      changed,
    }).toEqual({
      title: "Ship",
      listed: [created.id],
      changed: {
        accepted: [{ taskId: created.id, field: "title" }],
        rejected: [],
      },
    });
  });

  it("writes renamed event types and invalidates the block's queries", async () => {
    const events = await built.outbox.history().orThrow();
    const created = events.find((event) => event.type === "task.created");

    const queryClient = new QueryClient();
    const hub = new EventHub();
    const queries = blockQueries({ tasks: built.tasks });

    const stop = invalidateOnBlockEvents(
      queryClient,
      { events: hub },
      { tasks: blocks.blocks.tasks },
    );

    await queryClient.query(queries.tasks.list(TENANT));
    const key = queries.tasks.list(TENANT).queryKey;
    const before = queryClient.getQueryState(key)?.isInvalidated;

    if (created !== undefined) {
      // SAFETY: the outbox row is the `task.created` payload the SQL wrote.
      emitBlockEvent(hub, created.type, created.payload as never);
    }

    const after = queryClient.getQueryState(key)?.isInvalidated;
    stop();

    expect({
      types: events.map((event) => event.type),
      payload: Object.keys(created?.payload ?? {}).toSorted(),
      tenant: created?.tenant,
      before,
      after,
    }).toEqual({
      types: expect.arrayContaining(["task.created", "task.updated"]),
      // The tenant rename covers SQL names; JSON keys keep `organizationId`.
      payload: expect.arrayContaining(["organizationId", "taskId"]),
      tenant: TENANT,
      before: false,
      after: true,
    });
  });

  it("keeps a renamed task's files and checklist", async () => {
    const attachments = createAttachments({
      transport: sqlTransport(inTransaction(client)),
      schema: SCRATCH,
      storage: {
        from: () => ({
          createSignedUploadUrl: (path) =>
            Promise.resolve({
              data: { signedUrl: `https://storage.test/${path}`, token: "t" },
              error: null,
            }),
          createSignedUrl: (path) =>
            Promise.resolve({
              data: { signedUrl: `https://storage.test/${path}` },
              error: null,
            }),
          download: () => Promise.resolve({ data: new Blob([]), error: null }),
          remove: () => Promise.resolve({ data: [], error: null }),
        }),
      },
      tenant: TENANT,
    });

    const file = { name: "brief.pdf", mimeType: "application/pdf", size: 10 };
    const loose = await attachments.upload(null, file).orThrow();

    const task = await built.tasks
      .create(TENANT, { title: "Brief", attachmentIds: [loose.attachment.id] })
      .orThrow();

    const direct = await attachments
      .upload({ type: "task", id: task.id }, file)
      .orThrow();

    const listed = await attachments
      .list({ type: "task", id: task.id })
      .orThrow();

    const step = await built.tasks
      .saveChecklistItem(task.id, { title: "Read it" })
      .orThrow();

    const read = await built.tasks.get(task.id).orThrow();

    expect({
      files: listed.map((attachment) => attachment.id).toSorted(),
      subjects: listed.map((attachment) => attachment.subject?.type),
      step: step.title,
      checklist: read?.checklist,
    }).toEqual({
      files: [loose.attachment.id, direct.attachment.id].toSorted(),
      subjects: ["task", "task"],
      step: "Read it",
      checklist: { total: 1, done: 0 },
    });
  });

  it("runs a renamed block method as a Next.js action", async () => {
    const signer = await createTestSigner();
    const projectUrl = "https://abcdefghijklmnopqrst.supabase.co";

    const next = createNext(defineSupabase(schema), {
      env: {
        url: projectUrl,
        publishableKey: "sb_publishable_test",
        jwksUrl: new URL(`${projectUrl}/auth/v1/.well-known/jwks.json`),
      },
      auth: { jwks: signer.jwks },
    });

    mocks.headers = new Headers({
      authorization: `Bearer ${await signer.sign({ sub: "11111111-1111-4111-8111-111111111111" })}`,
    });

    const createTask = next.blockAction(() => built.tasks, "create", {
      input: v.object({ title: v.pipe(v.string(), v.minLength(1)) }),
      args: ({ title }) => [TENANT, { title }],
    });

    const created = await createTask({ title: "Review" });
    const invalid = await createTask({ title: "" });

    expect({ created, invalid }).toMatchObject({
      created: { ok: true, data: { title: "Review" } },
      invalid: { ok: false, error: { kind: "validation" } },
    });
  });
});
