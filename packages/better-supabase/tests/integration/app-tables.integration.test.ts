import { Pool } from "pg";
import { afterAll, afterEach, beforeEach, describe, expect, it } from "vitest";

import type { AppTablesConfig } from "../../src/config/types/app-tables.ts";
import type { ModuleLayout } from "../../src/sql/module-types.ts";

import { APP_TABLES_MODULE } from "../../src/sql/modules/app-tables.ts";
import { renderModules } from "../../src/sql/render.ts";
import {
  BlockSession,
  dbUrl,
  reachable,
  type TestUser,
} from "./block-session.ts";

const live = await reachable();

// The blocks and the app tables install inside a transaction that `close`
// rolls back (ADR 0040).
const TABLES: AppTablesConfig = {
  it_projects: {
    columns: {
      name: { type: "text", nullable: false },
      owner_id: {
        type: "uuid",
        references: { table: "auth.users", onDelete: "set null" },
      },
    },
  },
  it_tasks: {
    columns: {
      project_id: {
        type: "uuid",
        nullable: false,
        references: { table: "it_projects", onDelete: "cascade" },
      },
      title: { type: "text", nullable: false },
    },
  },
  it_notes: { scope: "user", columns: { body: { type: "text" } } },
  it_regions: { scope: "none", columns: { code: { type: "text" } } },
};

const BLOCKS = ["tenant", "organizations", "updated-at"];
const LAYOUT: ModuleLayout = { appTables: TABLES };

const pgtapFile = (): string =>
  renderModules(BLOCKS, LAYOUT).find(
    (file) => file.module === APP_TABLES_MODULE && file.kind === "test",
  )?.contents ?? "";

describe.skipIf(!live)("app tables", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  let s: BlockSession;
  let ann: TestUser;
  let bob: TestUser;
  let annOrg: string;
  let bobOrg: string;

  beforeEach(async () => {
    s = await BlockSession.open(pool);
    await s.install(BLOCKS, LAYOUT);
    ann = await s.user("ann");
    bob = await s.user("bob");
    annOrg = await s.organization(ann);
    bobOrg = await s.organization(bob);
  });

  afterEach(async () => {
    await s.close();
  });

  afterAll(async () => {
    await pool.end();
  });

  it("passes the pgTAP checks the module writes", async () => {
    // The session already holds the transaction the file opens and rolls back.
    const body = pgtapFile()
      .split("\n")
      .filter((line) => line !== "begin;" && line !== "rollback;")
      .join("\n");

    const results = await s.client.query(body);

    const lines = (Array.isArray(results) ? results : [results])
      .flatMap((result: { rows: Record<string, unknown>[] }) => result.rows)
      .flatMap((row) => Object.values(row))
      .filter((value): value is string => typeof value === "string");

    expect(lines.filter((line) => line.startsWith("not ok"))).toEqual([]);
    const planned = Number(/plan\((\d+)\)/u.exec(body)?.[1]);

    expect(planned).toBeGreaterThan(0);
    expect(lines.filter((line) => line.startsWith("ok")).length).toBe(planned);
  });

  it("keeps each organization's rows to its members", async () => {
    await s.asRole(ann);
    await s.client.query(
      "insert into public.it_projects (organization_id, name) values ($1, 'Launch')",
      [annOrg],
    );

    const projectId = await s.value<string>(
      "(select id::text from public.it_projects where name = 'Launch')",
    );

    await s.client.query(
      "insert into public.it_tasks (organization_id, project_id, title) values ($1, $2, 'Ship')",
      [annOrg, projectId],
    );

    expect(
      await s.hint(
        "insert into public.it_projects (organization_id, name) values ($1, 'Theft')",
        [bobOrg],
      ),
    ).toMatch(/row-level security/u);

    await s.asRole(bob);
    expect(
      await s.value<number>("(select count(*)::int from public.it_projects)"),
    ).toBe(0);
    expect(
      await s.value<number>("(select count(*)::int from public.it_tasks)"),
    ).toBe(0);

    await s.asRole(ann);
    expect(
      await s.value<number>("(select count(*)::int from public.it_tasks)"),
    ).toBe(1);
  });

  it("keeps a per-user table to its user and a shared table read-only", async () => {
    await s.asRole(ann);
    await s.client.query(
      "insert into public.it_notes (user_id, body) values ($1, 'mine')",
      [ann.id],
    );

    expect(
      await s.hint("insert into public.it_regions (code) values ('eu')"),
    ).toMatch(/GRANT INSERT ON public\.it_regions/u);

    await s.service();
    await s.client.query("insert into public.it_regions (code) values ('eu')");

    await s.asRole(bob);
    expect(
      await s.value<number>("(select count(*)::int from public.it_notes)"),
    ).toBe(0);
    expect(
      await s.value<number>("(select count(*)::int from public.it_regions)"),
    ).toBe(1);
  });
});
