import type { PoolClient } from "pg";

import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import { resolveConfig } from "../../src/config/resolve.ts";
import { moduleLayout } from "../../src/sql/layout.ts";
import { renderBlocks } from "../../src/sql/render.ts";
import { stackDbUrl } from "./stack-env.ts";

/** A scratch schema, so the stack's own block tables stay as they are. */
const SCRATCH = "bsb_instances";

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
      memberships: { schema: SCRATCH },
      permissions: { schema: SCRATCH },
      subjects: { schema: SCRATCH },
      outbox: { schema: SCRATCH },
      tags: { schema: SCRATCH },
      labels: { block: "tags", schema: SCRATCH, entities: { tag: "label" } },
      pipelines: { schema: SCRATCH },
      hiringPipelines: {
        block: "pipelines",
        schema: SCRATCH,
        entities: { pipeline: "hiring_pipeline" },
      },
      tasks: { schema: SCRATCH, uses: { pipelines: "pipelines" } },
      tickets: {
        block: "tasks",
        schema: SCRATCH,
        entities: { work_item: "ticket" },
        uses: { pipelines: "hiringPipelines" },
      },
    },
  },
  "/project",
);

describe.skipIf(!live)("block instances against Postgres", () => {
  let pool: Pool;
  let client: PoolClient;

  beforeAll(async () => {
    pool = new Pool({ connectionString: stackDbUrl(), max: 1 });
    client = await pool.connect();
    await client.query("begin");
    await client.query(`create schema ${SCRATCH}`);

    for (const file of renderBlocks(config.blockNames, moduleLayout(config))) {
      if (file.kind !== "test") {
        await client.query(file.contents);
      }
    }
  });

  afterAll(async () => {
    await client.query("rollback");
    client.release();
    await pool.end();
  });

  it("installs each instance's tables next to the block's", async () => {
    const { rows } = await client.query<{ name: string }>(
      `select table_name as name from information_schema.tables
       where table_schema = $1
         and table_name in ('tags', 'taggings', 'labels', 'labels_taggings',
           'pipelines', 'hiring_pipelines', 'tasks', 'tickets')
       order by 1`,
      [SCRATCH],
    );

    expect(rows.map((row) => row.name)).toStrictEqual([
      "hiring_pipelines",
      "labels",
      "labels_taggings",
      "pipelines",
      "taggings",
      "tags",
      "tasks",
      "tickets",
    ]);
  });

  it("records every instance with its block", async () => {
    const { rows } = await client.query<{ name: string; block: string }>(
      `select name, block from better_supabase.blocks
       where name in ('labels', 'hiringPipelines', 'tickets')
       order by 1`,
    );

    expect(rows).toStrictEqual([
      { name: "hiringPipelines", block: "pipelines" },
      { name: "labels", block: "tags" },
      { name: "tickets", block: "tasks" },
    ]);
  });
});
