import { Pool } from "pg";
import { afterAll, afterEach, beforeEach, describe, expect, it } from "vitest";

import type { AppTablesConfig } from "../../src/config/types/app-tables.ts";
import type { ModuleLayout } from "../../src/sql/module-types.ts";
import type { TestUser } from "./block-session.ts";

import { withAppTableSubjects } from "../../src/config/app-tables.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

// An app table that sets `subject` reaches the subject registry and the
// search index without a `subjects` entry (ADR 0043).
const TABLES: AppTablesConfig = {
  it_boards: {
    columns: { name: { type: "text", nullable: false } },
    subject: {
      type: "it_board",
      title: "name",
      url: "/boards/{id}",
      search: {},
      rank: true,
      softDelete: true,
    },
  },
};

const BLOCKS = ["tenant", "organizations", "updated-at", "subjects", "search"];

const LAYOUT: ModuleLayout = {
  appTables: TABLES,
  subjects: withAppTableSubjects({}, TABLES, undefined),
};

describe.skipIf(!live)("app table subjects", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  let s: BlockSession;
  let ann: TestUser;
  let annOrg: string;

  beforeEach(async () => {
    s = await BlockSession.open(pool);
    await s.install(BLOCKS, LAYOUT);
    ann = await s.user("ann");
    annOrg = await s.organization(ann);
  });

  afterEach(async () => {
    await s.close();
  });

  afterAll(async () => {
    await pool.end();
  });

  it("registers the table, adds rank and deleted_at, and indexes it for search", async () => {
    await s.asRole(ann);
    await s.client.query(
      "insert into public.it_boards (organization_id, name) values ($1, 'Roadmap')",
      [annOrg],
    );

    const id = await s.value<string>(
      "(select id::text from public.it_boards where name = 'Roadmap')",
    );

    expect(
      await s.value<string>(
        `(select better_supabase.subject_title('it_board', '${id}'))`,
      ),
    ).toBe("Roadmap");
    expect(
      await s.value<string>(
        `(select better_supabase.subject_url('it_board', '${id}'))`,
      ),
    ).toBe(`/boards/${id}`);
    expect(
      await s.value<string>(
        "(select rank || ':' || coalesce(deleted_at::text, 'live') from public.it_boards)",
      ),
    ).toBe("V:live");

    await s.service();
    expect(
      await s.value<number>(
        `(select count(*)::int from better_supabase.search_documents where subject_type = 'it_board' and subject_id = '${id}')`,
      ),
    ).toBe(1);
  });
});
