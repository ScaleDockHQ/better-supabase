import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { ModuleLayout } from "../../src/sql/module-types.ts";

import { createTrash, sqlTransport } from "../../src/blocks/trash/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const layout: ModuleLayout = {
  subjects: {
    project: {
      table: "trash_it.projects",
      idType: "uuid",
      title: "name",
      deletedAt: "deleted_at",
    },
    task: {
      table: "trash_it.tasks",
      idType: "uuid",
      title: "title",
      deletedAt: "deleted_at",
    },
    label: { table: "trash_it.labels", idType: "uuid" },
  },
  modules: {
    trash: {
      options: {
        retentionDays: 7,
        subjects: {
          project: {
            unique: ["slug"],
            children: [{ type: "task", column: "project_id" }],
          },
          task: {},
        },
      },
    },
  },
};

const TABLES = `create schema trash_it;
create table trash_it.projects (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  name text not null,
  slug text not null,
  deleted_at timestamptz
);
create unique index on trash_it.projects (organization_id, slug) where deleted_at is null;
create table trash_it.tasks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  project_id uuid references trash_it.projects (id),
  title text not null,
  deleted_at timestamptz
);
create table trash_it.labels (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
);`;

describe.skipIf(!live)("trash", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("trashes a subject with its children, restores, lists and purges", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.client.query(TABLES);
      await s.install(["organizations", "outbox", "trash"], layout);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const stranger = await s.user("stranger");
      const tenant = await s.organization(owner, { member });
      await s.organization(stranger);
      const trash = createTrash({ transport: sqlTransport(s.sql) });

      await s.service();
      const projects = await s.rows<{ id: string }>(
        `insert into trash_it.projects (organization_id, name, slug) values ($1, 'Launch', 'launch'), ($1, 'Archive', 'archive') returning id`,
        [tenant],
      );
      const project = projects[0]!.id;
      const other = projects[1]!.id;
      await s.client.query(
        `insert into trash_it.tasks (organization_id, project_id, title) values ($1, $2, 'Write'), ($1, $2, 'Ship'), ($1, null, 'Loose')`,
        [tenant, project],
      );
      const liveTasks = (): Promise<number> =>
        s.value<number>(
          "(select count(*)::int from trash_it.tasks where deleted_at is null)",
        );

      await s.as(member);
      const batch = await trash.trash(tenant, "project", project).orThrow();
      expect(batch.count).toBe(3);
      await s.service();
      expect(await liveTasks()).toBe(1);
      expect(
        await s.value<boolean>("better_supabase.is_trashed('project', $1)", [
          project,
        ]),
      ).toBe(true);

      await s.as(member);
      const listed = await trash.list(tenant).orThrow();
      expect(listed).toHaveLength(1);
      expect(listed[0]).toMatchObject({
        id: batch.id,
        subjectType: "project",
        title: "Launch",
        count: 3,
      });
      expect(listed[0]!.purgeAfter).toBeDefined();
      expect(
        await trash
          .trash(tenant, "project", project)
          .then((r) => !r.ok && r.error.hint),
      ).toBe("TRASH_NOT_FOUND");
      expect(
        await trash
          .trash(tenant, "label", project)
          .then((r) => !r.ok && r.error.hint),
      ).toBe("TRASH_FORBIDDEN");

      await s.service();
      await s.client.query(
        `insert into trash_it.projects (organization_id, name, slug) values ($1, 'Launch 2', 'launch')`,
        [tenant],
      );
      await s.as(member);
      expect(
        await trash.restore(batch.id).then((r) => !r.ok && r.error.hint),
      ).toBe("TRASH_RESTORE_CONFLICT");
      await s.service();
      await s.client.query(
        "update trash_it.projects set slug = 'launch-2' where slug = 'launch' and deleted_at is null",
      );
      await s.as(member);
      expect(await trash.restore(batch.id).orThrow()).toMatchObject({
        count: 3,
      });
      await s.service();
      expect(await liveTasks()).toBe(3);
      expect(await trash.list(tenant).orThrow()).toEqual([]);

      await s.as(stranger);
      expect(
        await trash
          .trash(tenant, "project", other)
          .then((r) => !r.ok && r.error.hint),
      ).toBe("TRASH_FORBIDDEN");

      await s.as(member);
      const gone = await trash.trash(tenant, "project", other).orThrow();
      expect(
        await trash.purge(gone.id).then((r) => !r.ok && r.error.hint),
      ).toBe("TRASH_FORBIDDEN");
      await s.as(owner);
      expect(await trash.purge(gone.id).orThrow()).toBe(1);
      await s.service();
      expect(
        await s.value<number>(
          "(select count(*)::int from trash_it.projects where id = $1)",
          [other],
        ),
      ).toBe(0);

      await s.as(member);
      const expiring = await trash.trash(tenant, "project", project).orThrow();
      await s.service();
      await s.client.query(
        "update better_supabase.trash_items set purge_after = now() - interval '1 day' where batch_id = $1",
        [expiring.batchId],
      );
      expect(
        await s.value<number>("better_supabase.purge_expired_trash()"),
      ).toBe(3);
      expect(
        await s.value<number>(
          "(select count(*)::int from trash_it.tasks where project_id = $1)",
          [project],
        ),
      ).toBe(0);
      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where organization_id = $1 and type like 'subject.%' order by position",
        [tenant],
      );
      expect(new Set(events.map((event) => event.type))).toEqual(
        new Set(["subject.trashed", "subject.restored", "subject.purged"]),
      );
    } finally {
      await s.close();
    }
  });
});
