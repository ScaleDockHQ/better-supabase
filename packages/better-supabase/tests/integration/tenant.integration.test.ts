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
});
