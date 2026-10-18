import type { PoolClient, QueryArrayResult } from "pg";

import { resolveConfig } from "better-supabase/config";
import { moduleLayout, renderModules } from "better-supabase/sql";
import { randomUUID } from "node:crypto";
import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { dbUrl, installAndRollBack, reachable } from "./stack.ts";

// `appTables` (ADR 0040) on top of the tenant and organizations blocks, installed as one
// migration: the generated pgTAP checks pass, and RLS keeps one tenant's
// rows from another tenant's members.

const live = await reachable();

const config = resolveConfig(
  {
    blocks: ["tenant", "organizations"],
    appTables: {
      projects: {
        columns: { name: { type: "text", nullable: false } },
      },
      tasks: {
        columns: {
          project_id: {
            type: "uuid",
            nullable: false,
            references: { table: "projects", onDelete: "cascade" },
          },
          title: { type: "text", nullable: false },
        },
      },
      drafts: { scope: "user", columns: { body: { type: "text" } } },
      changelog: { scope: "none", columns: { body: { type: "text" } } },
    },
  },
  process.cwd(),
);

const files = renderModules(config.blockNames, moduleLayout(config));

const schema = files
  .filter((file) => file.kind !== "test")
  .map((file) => file.contents)
  .join("\n\n");

const appTest =
  files.find((file) => file.kind === "test" && file.module === "app-tables")
    ?.contents ?? "";

const pgtapBody = appTest
  .split("\n")
  .filter((line) => line !== "begin;" && line !== "rollback;")
  .join("\n");

async function asUser(client: PoolClient, sub: string): Promise<void> {
  await client.query(
    "select set_config('request.jwt.claims', json_build_object('sub', $1::text, 'role', 'authenticated')::text, true)",
    [sub],
  );
  await client.query("set local role authenticated");
}

describe.skipIf(!live)("appTables on the local stack", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  afterAll(() => pool.end());

  it("passes the generated pgTAP checks", async () => {
    await installAndRollBack(pool, schema, async (client) => {
      const results: unknown = await client.query({
        text: pgtapBody,
        rowMode: "array",
      });

      const lines = (Array.isArray(results) ? results : [results])
        .flatMap((result: QueryArrayResult) => result.rows.flat())
        .filter((value): value is string => typeof value === "string");

      expect(lines.filter((line) => line.startsWith("not ok"))).toEqual([]);
      expect(lines.filter((line) => line.startsWith("ok ")).length).toBe(
        Number(/plan\((\d+)\)/.exec(appTest)?.[1]),
      );
    });
  }, 120_000);

  it("keeps a tenant's rows from another tenant's members", async () => {
    await installAndRollBack(pool, schema, async (client) => {
      const ids = {
        a: randomUUID(),
        b: randomUUID(),
        owner: randomUUID(),
        stranger: randomUUID(),
      };

      await client.query(
        "insert into auth.users (id, email) values ($1, 'owner@app-tables.test'), ($2, 'stranger@app-tables.test')",
        [ids.owner, ids.stranger],
      );
      await client.query(
        "insert into better_supabase.organizations (id, name, slug) values ($1, 'A', 'app-tables-a'), ($2, 'B', 'app-tables-b')",
        [ids.a, ids.b],
      );
      await client.query(
        "insert into better_supabase.memberships (organization_id, user_id, role) values ($1, $2, 'owner'), ($3, $4, 'owner')",
        [ids.a, ids.owner, ids.b, ids.stranger],
      );

      await asUser(client, ids.owner);
      await client.query(
        "insert into public.projects (organization_id, name) values ($1, 'Launch')",
        [ids.a],
      );
      await client.query("insert into public.drafts (body) values ('mine')");

      const own = await client.query("select name from public.projects");

      expect(own.rows).toEqual([{ name: "Launch" }]);

      await client.query("reset role");
      await asUser(client, ids.stranger);

      const projects = await client.query("select * from public.projects");
      const drafts = await client.query("select * from public.drafts");

      expect(projects.rows).toEqual([]);
      expect(drafts.rows).toEqual([]);
      await expect(
        client.query(
          "insert into public.projects (organization_id, name) values ($1, 'Takeover')",
          [ids.a],
        ),
      ).rejects.toMatchObject({ code: "42501" });
    });
  }, 120_000);
});
