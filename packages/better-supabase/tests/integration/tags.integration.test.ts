import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { createTags } from "../../src/blocks/tags/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)("tags", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("lists the tenant's tags and a readable subject's tags", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.rows(
        `create table if not exists public.bsb_test_projects (
           id uuid primary key default gen_random_uuid(),
           organization_id uuid not null,
           name text not null
         );
         alter table public.bsb_test_projects enable row level security;
         grant select on public.bsb_test_projects to authenticated;
         drop policy if exists "read" on public.bsb_test_projects;
         create policy "read" on public.bsb_test_projects for select to authenticated
           using (better_supabase.has_organization_role(organization_id));`,
      );
      await s.install(["organizations", "tags"], {
        modules: { tags: { on: { project: { table: "bsb_test_projects" } } } },
      });
      const owner = await s.user("owner");
      const member = await s.user("member");
      const outsider = await s.user("outsider");
      const org = await s.organization(owner, { member });

      const [inserted] = await s.rows<{ id: string }>(
        "insert into public.bsb_test_projects (organization_id, name) values ($1, 'Apollo') returning id",
        [org],
      );

      const project = inserted!.id;
      const tags = createTags({ transport: sqlTransport(s.sql), tenant: org });
      const subject = { type: "project", id: project };

      await s.as(owner);
      const vip = await tags.create({ kind: "project", name: "VIP" }).orThrow();

      const risk = await tags
        .create({ kind: "project", name: "At risk" })
        .orThrow();

      await tags.create({ kind: "invoice", name: "Overdue" }).orThrow();

      await s.asRole(member);
      expect(
        (await tags.list({ kind: "project" }).orThrow()).map((tag) => tag.name),
      ).toEqual(["VIP", "At risk"]);
      expect((await tags.list().orThrow()).map((tag) => tag.kind)).toEqual(
        expect.arrayContaining(["project", "invoice"]),
      );
      expect(await tags.list({ on: subject }).orThrow()).toEqual([]);
      await tags.attach(subject, risk.id).orThrow();
      await tags.attach(subject, vip.id).orThrow();
      expect(
        (await tags.list({ on: subject }).orThrow()).map((tag) => tag.id),
      ).toEqual([vip.id, risk.id]);

      await s.asRole(outsider);
      expect((await tags.list()).error?.hint).toBe("TAG_FORBIDDEN");
      expect((await tags.list({ on: subject })).error?.hint).toBe(
        "TAG_FORBIDDEN",
      );
    } finally {
      await s.close();
    }
  });
});
