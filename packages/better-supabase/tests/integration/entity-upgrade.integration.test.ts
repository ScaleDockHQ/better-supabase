import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { createWorkItems } from "../../src/blocks/work-items/index.ts";
import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { entityRenamePlan } from "../../src/sql/entity-upgrade.ts";
import { renderBlocks } from "../../src/sql/render.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MODULES = [
  "organizations",
  "outbox",
  "subjects",
  "rank",
  "pipelines",
  "work-items",
  "access",
  "messaging",
  "comments",
];

const layout = (entities?: Record<string, string>): BlockSqlLayout => {
  const blocks = entities ? { "work-items": { entities } } : {};

  return {
    subjects: withBlockSubjects({}, ["work-items"], blocks),
    modules: blocks,
  };
};

// The subjects, messaging and comments modules read block tables that install after
// them, and the tenant module resets check_function_bodies, so each file
// turns it off again.
async function install(s: BlockSession, at: BlockSqlLayout): Promise<void> {
  for (const file of renderBlocks(MODULES, at)) {
    if (file.kind !== "test") {
      await s.client.query("set local check_function_bodies = off");
      await s.client.query(file.contents);
    }
  }
}

describe.skipIf(!live)(
  "sql upgrade renames an installed block's entities",
  () => {
    const pool = new Pool({ connectionString: dbUrl, max: 1 });

    afterAll(() => pool.end());

    it("renames tables, functions and stored subjects and keeps the rows", async () => {
      const s = await BlockSession.open(pool);

      try {
        await s.client.query("drop schema if exists better_supabase cascade");
        const owner = await s.user("owner");
        const installed = renderBlocks(MODULES, layout());
        await install(s, layout());
        const org = await s.organization(owner);

        await s.as(owner);

        const item = await createWorkItems({ transport: sqlTransport(s.sql) })
          .create(org, { title: "Renamed later" })
          .orThrow();

        await s.client.query(
          "select better_supabase.create_comment($1, 'work_item', $2, 'Still here')",
          [org, item.id],
        );
        await s.service();

        const tasks = layout({ work_item: "task" });

        const plan = entityRenamePlan(
          MODULES,
          [...new Set(installed.map((file) => file.module))],
          installed.map((file) => file.contents).join("\n"),
          tasks,
        );

        expect(plan.refused).toEqual([]);

        for (const step of plan.steps) {
          await s.client.query(step.sql);
        }

        await install(s, tasks);

        const { rows } = await s.client.query<{
          title: string;
          subject: string;
          old: string | null;
        }>(
          `select t.title, c.subject_type as subject,
           to_regprocedure('better_supabase.create_work_item(uuid, jsonb)')::text as old
         from better_supabase.tasks t
         join better_supabase.conversations c on c.subject_id = t.id::text`,
        );

        expect(rows).toEqual([
          { title: "Renamed later", subject: "task", old: null },
        ]);
        expect(
          (
            await s.client.query(
              "select to_regclass('better_supabase.work_items') as old",
            )
          ).rows[0],
        ).toEqual({ old: null });
      } finally {
        await s.close();
      }
    });
  },
);
