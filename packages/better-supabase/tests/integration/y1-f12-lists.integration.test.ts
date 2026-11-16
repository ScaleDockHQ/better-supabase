import { Pool } from "pg";
import { afterAll, describe, it } from "vitest";

import { createMemory, sqlTransport } from "../../src/blocks/memory/index.ts";
import { testBlockList } from "../../src/testing/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";
import { wordEmbedder } from "./word-embedder.ts";

const live = await reachable();

/** One transaction gives every row the same now(); a sort needs distinct values. */
async function spreadTimes(
  s: BlockSession,
  table: string,
  columns: readonly string[],
): Promise<void> {
  await s.client.query("reset role");
  await s.client.query(
    `update better_supabase.${table} a set ${columns.map((column) => `${column} = now() + (r.n || ' minutes')::interval`).join(", ")} from (select id, row_number() over (order by random()) as n from better_supabase.${table}) r where r.id = a.id`,
  );
}

describe.skipIf(!live)("the F12 block lists follow the list contract", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("pages archival memories of a namespace", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(["organizations", "ai-chat", "memory"]);
      const owner = await s.user("memory-owner");
      const org = await s.organization(owner);

      const memory = createMemory({
        transport: sqlTransport(s.sql),
        embedder: wordEmbedder(),
      });

      await s.asRole(owner);

      for (const [content, category] of [
        ["Rex is a dog", "pet"],
        ["Rexona is a cat", "pet"],
        ["Likes green tea", "taste"],
        ["Works from Lisbon", "work"],
        ["Plays the cello", "taste"],
      ] as const) {
        await memory.archival
          .upsert({ organizationId: org, content, category })
          .orThrow();
      }

      await spreadTimes(s, "memories", ["created_at", "updated_at"]);
      await s.asRole(owner);

      await testBlockList({
        name: "memory.archival",
        target: {
          page: (options) =>
            memory.archival.page({ ...options, organizationId: org }),
          count: (options) =>
            memory.archival.count({ ...options, organizationId: org }),
          facets: (options) =>
            memory.archival.facets({ ...options, organizationId: org }),
          get: (id) => memory.archival.get(id),
        },
        rows: 5,
        sorts: ["createdAt", "updatedAt"],
        facets: { category: { pet: 2, taste: 2, work: 1 } },
        arrayFilter: { column: "category", values: ["pet", "work"] },
        search: "rex",
      });
    } finally {
      await s.close();
    }
  });
});
