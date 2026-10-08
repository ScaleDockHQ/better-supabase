import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)("tenant sameTenant", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("refuses a reference to another tenant's row for every writer", async () => {
    const s = await BlockSession.open(pool);
    const suffix = crypto.randomUUID().slice(0, 8);
    const projects = `public.bs_projects_${suffix}`;
    const tasks = `public.bs_tasks_${suffix}`;
    try {
      await s.client.query(`
        create table ${projects} (
          id uuid primary key default gen_random_uuid(),
          organization_id uuid not null,
          kind text not null default 'project'
        );
        create table ${tasks} (
          id uuid primary key default gen_random_uuid(),
          organization_id uuid not null,
          project_id uuid references ${projects} (id),
          template_id uuid references ${projects} (id)
        );
        grant select, insert, update on ${projects}, ${tasks} to authenticated;`);
      await s.install(["tenant"], {
        modules: {
          tenant: {
            options: {
              sameTenant: [
                { table: tasks, column: "project_id", references: projects },
                {
                  table: tasks,
                  column: "template_id",
                  references: {
                    table: projects,
                    where: "{row}.kind = 'template'",
                  },
                },
              ],
            },
          },
        },
      });
      const a = crypto.randomUUID();
      const b = crypto.randomUUID();
      const [own, other, template] = await s.rows<{ id: string }>(
        `insert into ${projects} (organization_id, kind)
         values ($1, 'project'), ($2, 'project'), ($1, 'template') returning id`,
        [a, b],
      );
      await s.service();
      expect(
        await s.hint(
          `insert into ${tasks} (organization_id, project_id) values ($1, $2)`,
          [a, other!.id],
        ),
      ).toBe("TENANT_MISMATCH");
      expect(
        await s.hint(
          `insert into ${tasks} (organization_id, project_id, template_id) values ($1, $2, null)`,
          [a, own!.id],
        ),
      ).toBe("no error");
      expect(
        await s.hint(
          `insert into ${tasks} (organization_id, template_id) values ($1, $2)`,
          [a, own!.id],
        ),
      ).toBe("TENANT_MISMATCH");
      expect(
        await s.hint(
          `insert into ${tasks} (organization_id, template_id) values ($1, $2)`,
          [a, template!.id],
        ),
      ).toBe("no error");
      expect(
        await s.hint(
          `update ${tasks} set project_id = $1 where project_id = $2`,
          [other!.id, own!.id],
        ),
      ).toBe("TENANT_MISMATCH");
      expect(
        await s.hint(
          `update ${tasks} set organization_id = $1 where project_id = $2`,
          [b, own!.id],
        ),
      ).toBe("TENANT_MISMATCH");

      const user = await s.user("member");
      await s.asRole(user);
      expect(
        await s.hint(
          `insert into ${tasks} (organization_id, project_id) values ($1, $2)`,
          [b, own!.id],
        ),
      ).toBe("TENANT_MISMATCH");
      expect(
        await s.hint(
          `insert into ${tasks} (organization_id, project_id) values ($1, $2)`,
          [b, other!.id],
        ),
      ).toBe("no error");
    } finally {
      await s.close();
    }
  });

  it("also requires the referenced row to match the row's columns", async () => {
    const s = await BlockSession.open(pool);
    const suffix = crypto.randomUUID().slice(0, 8);
    const assets = `public.bs_assets_${suffix}`;
    const jobs = `public.bs_jobs_${suffix}`;
    try {
      await s.client.query(`
        create table ${assets} (
          id uuid primary key default gen_random_uuid(),
          organization_id uuid not null,
          customer_id uuid
        );
        create table ${jobs} (
          id uuid primary key default gen_random_uuid(),
          organization_id uuid not null,
          customer_id uuid,
          asset_id uuid references ${assets} (id)
        );
        grant select, insert, update on ${assets}, ${jobs} to authenticated;`);
      await s.install(["tenant"], {
        modules: {
          tenant: {
            options: {
              sameTenant: [
                {
                  table: jobs,
                  column: "asset_id",
                  references: assets,
                  match: { customer_id: "customer_id" },
                },
              ],
            },
          },
        },
      });
      const a = crypto.randomUUID();
      const b = crypto.randomUUID();
      const alice = crypto.randomUUID();
      const bob = crypto.randomUUID();
      const [aliceAsset, bobAsset, looseAsset, otherTenant] = await s.rows<{
        id: string;
      }>(
        `insert into ${assets} (organization_id, customer_id)
         values ($1, $3), ($1, $4), ($1, null), ($2, $3) returning id`,
        [a, b, alice, bob],
      );
      const insert = `insert into ${jobs} (organization_id, customer_id, asset_id) values ($1, $2, $3)`;

      expect(await s.hint(insert, [a, alice, bobAsset!.id])).toBe(
        "TENANT_MISMATCH",
      );
      expect(await s.hint(insert, [a, alice, aliceAsset!.id])).toBe("no error");

      await s.service();
      expect(await s.hint(insert, [a, alice, bobAsset!.id])).toBe(
        "TENANT_MISMATCH",
      );
      expect(await s.hint(insert, [a, alice, otherTenant!.id])).toBe(
        "TENANT_MISMATCH",
      );
      expect(await s.hint(insert, [a, null, looseAsset!.id])).toBe("no error");
      expect(await s.hint(insert, [a, null, aliceAsset!.id])).toBe(
        "TENANT_MISMATCH",
      );
      expect(await s.hint(insert, [a, alice, null])).toBe("no error");
      expect(
        await s.hint(
          `update ${jobs} set customer_id = $1 where asset_id = $2`,
          [bob, aliceAsset!.id],
        ),
      ).toBe("TENANT_MISMATCH");
      expect(
        await s.hint(
          `update ${jobs} set customer_id = $1, asset_id = $2 where asset_id = $3`,
          [bob, bobAsset!.id, aliceAsset!.id],
        ),
      ).toBe("no error");

      const user = await s.user("member");
      await s.asRole(user);
      expect(await s.hint(insert, [a, bob, aliceAsset!.id])).toBe(
        "TENANT_MISMATCH",
      );
      expect(await s.hint(insert, [a, bob, bobAsset!.id])).toBe("no error");
    } finally {
      await s.close();
    }
  });
  it("matches a column reached through another reference", async () => {
    const s = await BlockSession.open(pool);
    const suffix = crypto.randomUUID().slice(0, 8);
    const quotes = `public.bs_quotes_${suffix}`;
    const assets = `public.bs_assets_${suffix}`;
    const lines = `public.bs_quote_assets_${suffix}`;
    try {
      await s.client.query(`
        create table ${quotes} (
          id uuid primary key default gen_random_uuid(),
          organization_id uuid not null,
          customer_id uuid
        );
        create table ${assets} (
          id uuid primary key default gen_random_uuid(),
          organization_id uuid not null,
          customer_id uuid
        );
        create table ${lines} (
          id uuid primary key default gen_random_uuid(),
          organization_id uuid not null,
          quote_id uuid references ${quotes} (id),
          asset_id uuid references ${assets} (id)
        );`);
      await s.install(["tenant"], {
        modules: {
          tenant: {
            options: {
              sameTenant: [
                {
                  table: lines,
                  column: "asset_id",
                  references: assets,
                  match: { "quote_id.customer_id": "customer_id" },
                  through: { quote_id: quotes },
                },
              ],
            },
          },
        },
      });
      const a = crypto.randomUUID();
      const alice = crypto.randomUUID();
      const bob = crypto.randomUUID();
      const [aliceQuote, bobQuote] = await s.rows<{ id: string }>(
        `insert into ${quotes} (organization_id, customer_id) values ($1, $2), ($1, $3) returning id`,
        [a, alice, bob],
      );
      const [aliceAsset, bobAsset] = await s.rows<{ id: string }>(
        `insert into ${assets} (organization_id, customer_id) values ($1, $2), ($1, $3) returning id`,
        [a, alice, bob],
      );
      const insert = `insert into ${lines} (organization_id, quote_id, asset_id) values ($1, $2, $3)`;

      await s.service();
      expect(await s.hint(insert, [a, aliceQuote!.id, bobAsset!.id])).toBe(
        "TENANT_MISMATCH",
      );
      expect(await s.hint(insert, [a, aliceQuote!.id, aliceAsset!.id])).toBe(
        "no error",
      );
      expect(
        await s.hint(`update ${lines} set quote_id = $1 where asset_id = $2`, [
          bobQuote!.id,
          aliceAsset!.id,
        ]),
      ).toBe("TENANT_MISMATCH");
      expect(
        await s.hint(
          `update ${lines} set quote_id = $1, asset_id = $2 where asset_id = $3`,
          [bobQuote!.id, bobAsset!.id, aliceAsset!.id],
        ),
      ).toBe("no error");
    } finally {
      await s.close();
    }
  });
});
