import { Pool } from "pg";
import { afterAll, afterEach, beforeEach, describe, expect, it } from "vitest";

import type { AppTablesConfig } from "../../src/config/types/app-tables.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";
import type { TestUser } from "./block-session.ts";

import { APP_TABLES_MODULE } from "../../src/sql/modules/app-tables.ts";
import { renderBlocks } from "../../src/sql/render.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

// The blocks and the app tables install inside a transaction that `close`
// rolls back (ADR 0040).
const TABLES: AppTablesConfig = {
  it_projects: {
    unique: [["organization_id", "code"]],
    indexes: [["stage", "created_at"]],
    comment: "Projects of a team.",
    columns: {
      name: { type: "text", nullable: false, max: 80 },
      owner_id: {
        type: "uuid",
        references: { table: "auth.users", onDelete: "set null" },
      },
      email: { type: "text", format: "email" },
      stage: { type: "text", options: ["draft", "live"] },
      labels: { type: "text[]", options: ["red", "blue"] },
      rating: { type: "integer", format: "rating" },
      code: { type: "text", comment: "A short code." },
    },
    rollups: {
      task_count: { table: "it_tasks", via: "project_id", aggregate: "count" },
      done_count: {
        table: "it_tasks",
        via: "project_id",
        aggregate: "count",
        where: { column: "status", equals: "done" },
      },
      effort_total: {
        table: "it_tasks",
        via: "project_id",
        aggregate: "sum",
        column: "effort",
      },
    },
  },
  it_tickets: {
    id: "bigint",
    columns: { number: { type: "bigint", identity: true } },
  },
  it_ticket_notes: {
    columns: {
      ticket_id: {
        type: "bigint",
        references: { table: "it_tickets", onDelete: "cascade" },
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
      status: { type: "text", options: ["todo", "done"] },
      effort: { type: "integer" },
    },
    lookups: { project_name: { via: "project_id", column: "name" } },
  },
  it_notes: { scope: "user", columns: { body: { type: "text" } } },
  it_regions: { scope: "none", columns: { code: { type: "text" } } },
};

const BLOCKS = ["tenant", "organizations", "updated-at"];
const LAYOUT: BlockSqlLayout = { appTables: TABLES };

const pgtapFile = (): string =>
  renderBlocks(BLOCKS, LAYOUT).find(
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
    expect(lines.filter((line) => line.startsWith("ok"))).toHaveLength(planned);
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

  it("reads rollups and lookups through the view, with the caller's row level security", async () => {
    await s.asRole(ann);
    await s.client.query(
      "insert into public.it_projects (organization_id, name) values ($1, 'Launch'), ($1, 'Empty')",
      [annOrg],
    );

    const projectId = await s.value<string>(
      "(select id::text from public.it_projects where name = 'Launch')",
    );

    await s.client.query(
      `insert into public.it_tasks (organization_id, project_id, title, status, effort)
       values ($1, $2, 'Plan', 'done', 3), ($1, $2, 'Ship', 'todo', 5)`,
      [annOrg, projectId],
    );

    const { rows } = await s.client.query<{
      name: string;
      task_count: string;
      done_count: string;
      effort_total: string;
    }>(
      "select name, task_count::text, done_count::text, effort_total::text from public.it_projects_view order by name",
    );

    expect(rows).toEqual([
      { name: "Empty", task_count: "0", done_count: "0", effort_total: "0" },
      { name: "Launch", task_count: "2", done_count: "1", effort_total: "8" },
    ]);
    expect(
      await s.value<string>(
        "(select string_agg(distinct project_name, ',') from public.it_tasks_view)",
      ),
    ).toBe("Launch");
    expect(
      await s.hint(
        "update public.it_projects_view set name = 'Renamed' where name = 'Launch'",
      ),
    ).toMatch(/enable updating the view/u);

    await s.asRole(bob);
    expect(
      await s.value<number>(
        "(select count(*)::int from public.it_projects_view)",
      ),
    ).toBe(0);
    expect(
      await s.value<number>("(select count(*)::int from public.it_tasks_view)"),
    ).toBe(0);
  });

  it("refuses a reference to a row of another organization", async () => {
    await s.asRole(bob);
    await s.client.query(
      "insert into public.it_projects (organization_id, name) values ($1, 'Secret')",
      [bobOrg],
    );

    await s.service();

    const projectId = await s.value<string>(
      "(select id::text from public.it_projects where name = 'Secret')",
    );

    await s.asRole(ann);
    expect(
      await s.hint(
        "insert into public.it_tasks (organization_id, project_id, title) values ($1, $2, 'Peek')",
        [annOrg, projectId],
      ),
    ).toContain("it_tasks_project_id_fkey");
  });

  it("checks formats, options, bounds and composite unique keys", async () => {
    await s.asRole(ann);

    const insert = (columns: string, values: string): Promise<string> =>
      s.hint(
        `insert into public.it_projects (organization_id, name, ${columns}) values ($1, 'P', ${values})`,
        [annOrg],
      );

    for (const [columns, values, constraint] of [
      ["email", "'nope'", "it_projects_email_check"],
      ["stage", "'archived'", "it_projects_stage_check"],
      ["labels", "array['green']", "it_projects_labels_check"],
      ["rating", "6", "it_projects_rating_check"],
    ] as const) {
      expect(await insert(columns, values)).toContain(constraint);
    }

    expect(
      await s.hint(
        `insert into public.it_projects (organization_id, name) values ($1, repeat('x', 81))`,
        [annOrg],
      ),
    ).toContain("it_projects_name_check");

    await s.client.query(
      "insert into public.it_projects (organization_id, name, email, stage, labels, rating, code) values ($1, 'A', 'a@example.com', 'live', array['red'], 5, 'A1')",
      [annOrg],
    );
    expect(await insert("code", "'A1'")).toContain(
      "it_projects_organization_id_code_key",
    );

    await s.client.query(
      "insert into public.it_tickets (organization_id) values ($1), ($1)",
      [annOrg],
    );
    expect(
      await s.value<string>(
        "(select string_agg(number::text, ',' order by number) from public.it_tickets)",
      ),
    ).toBe("1,2");
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
