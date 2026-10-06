import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type {
  LifecycleStorage,
  StorageEntry,
} from "../../src/blocks/data-lifecycle/index.ts";

import {
  createDataExporter,
  createDataLifecycle,
  createOrganizationPurger,
  sqlTransport,
} from "../../src/blocks/data-lifecycle/index.ts";
import { ok } from "../../src/core/result.ts";
import { AsyncResult } from "../../src/core/result.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

/** An in-memory bucket store keyed by path. */
function memoryStorage() {
  const files = new Map<string, string>();
  const storage: LifecycleStorage = {
    from: () => ({
      upload: async (path, body) => {
        files.set(path, await body.text());
        return { data: { path }, error: null };
      },
      createSignedUrl: (path) =>
        Promise.resolve({
          data: { signedUrl: `https://storage.test/${path}` },
          error: null,
        }),
      list: (prefix = "") => {
        const entries = new Map<string, StorageEntry>();
        for (const path of files.keys()) {
          if (!path.startsWith(`${prefix}/`)) continue;
          const [name, ...rest] = path.slice(prefix.length + 1).split("/");
          entries.set(name!, {
            name: name!,
            id: rest.length > 0 ? null : path,
          });
        }
        return Promise.resolve({ data: [...entries.values()], error: null });
      },
      remove: (paths) => {
        for (const path of paths) files.delete(path);
        return Promise.resolve({ data: [], error: null });
      },
    }),
  };
  return { files, storage };
}

describe.skipIf(!live)("data lifecycle", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("exports a user's and an organization's rows to NDJSON files", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.rows(
        `create table if not exists public.bs_test_lifecycle (
           id uuid primary key default gen_random_uuid(),
           organization_id uuid not null,
           owner_id uuid,
           name text not null
         );`,
      );
      await s.install(
        ["organizations", "outbox", "settings", "comments", "data-lifecycle"],
        {
          modules: {
            "data-lifecycle": {
              options: {
                tables: {
                  "public.bs_test_lifecycle": {
                    tenant: "organization_id",
                    user: "owner_id",
                  },
                },
              },
            },
          },
        },
      );
      const owner = await s.user("owner");
      const member = await s.user("member");
      const organization = await s.organization(owner, { member });
      await s.rows(
        "insert into public.bs_test_lifecycle (organization_id, owner_id, name) select $1, $2, 'p' || g from generate_series(1, 3) g",
        [organization, member.id],
      );
      const lifecycle = createDataLifecycle({ transport: sqlTransport(s.sql) });

      await s.asRole(member);
      const mine = await lifecycle.requestExport().orThrow();
      expect(mine).toMatchObject({
        subject: "user",
        userId: member.id,
        status: "pending",
      });
      expect((await lifecycle.requestExport().orThrow()).id).toBe(mine.id);
      const denied = await lifecycle.requestExport({
        organizationId: organization,
      });
      expect(denied.ok ? undefined : denied.error.hint).toBe(
        "DATA_EXPORT_FORBIDDEN",
      );
      expect(
        (await lifecycle.exports().orThrow()).map((row) => row.id),
      ).toEqual([mine.id]);

      await s.asRole(owner);
      const theirs = await lifecycle
        .requestExport({ organizationId: organization })
        .orThrow();
      expect(theirs.subject).toBe("organization");

      await s.service();
      const memory = memoryStorage();
      const exporter = createDataExporter({
        transport: sqlTransport(s.sql),
        storage: memory.storage,
        pageSize: 2,
      });
      const ready = await exporter.run(mine.id).orThrow();
      expect(ready.status).toBe("ready");
      expect(ready.expiresAt).toBeDefined();
      expect(ready.files).toContain(
        `${mine.id}/public.bs_test_lifecycle.ndjson`,
      );
      const lines = memory.files
        .get(`${mine.id}/public.bs_test_lifecycle.ndjson`)!
        .trim()
        .split("\n")
        .map((line) => JSON.parse(line) as { name: string });
      expect(lines.map((row) => row.name).sort()).toEqual(["p1", "p2", "p3"]);
      const memberships = memory.files.get(
        `${mine.id}/better_supabase.memberships.ndjson`,
      )!;
      expect(memberships).toContain(member.id);
      expect(memberships).not.toContain(owner.id);
      expect((await exporter.run(mine.id)).ok).toBe(false);

      await exporter.sink().send([
        {
          specversion: "1.0",
          id: "e1",
          source: "/t",
          type: "dev.better-supabase.data_export.requested",
          data: { exportId: theirs.id },
        },
      ]);
      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where type like 'data_export.%' order by position",
      );
      expect(events.map((event) => event.type)).toEqual([
        "data_export.requested",
        "data_export.requested",
        "data_export.ready",
        "data_export.ready",
      ]);
      const organizationFile = memory.files.get(
        `${theirs.id}/better_supabase.memberships.ndjson`,
      )!;
      expect(organizationFile).toContain(owner.id);
      expect(organizationFile).toContain(member.id);

      await s.rows(
        "insert into storage.objects (bucket_id, name, metadata) values ('data-exports', $1, '{}')",
        [ready.files[0]],
      );
      const visible = () =>
        s.value<number>(
          "(select count(*)::int from storage.objects where bucket_id = 'data-exports')",
        );
      await s.asRole(member);
      expect(await visible()).toBe(1);
      const download = await createDataLifecycle({
        transport: sqlTransport(s.sql),
        storage: memory.storage,
      })
        .download(mine.id)
        .orThrow();
      expect(download.files.map((file) => file.table)).toContain(
        "public.bs_test_lifecycle",
      );
      await s.asRole(owner);
      expect(await visible()).toBe(0);
      expect((await lifecycle.download(mine.id)).ok).toBe(false);
    } finally {
      await s.close();
    }
  });

  it("disables a tenant for the grace period, cancels and purges", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.rows(
        `create table if not exists public.bs_test_lifecycle (
           id uuid primary key default gen_random_uuid(),
           organization_id uuid not null,
           owner_id uuid,
           name text not null
         );
         create table if not exists public.bs_test_purges (organization_id uuid);
         create or replace function public.on_organization_purge(tenant uuid)
         returns void language sql as $$ insert into public.bs_test_purges values (tenant) $$;`,
      );
      await s.install(
        ["organizations", "outbox", "settings", "data-lifecycle"],
        {
          modules: {
            "data-lifecycle": {
              options: {
                tables: {
                  bs_test_lifecycle: { tenant: "organization_id" },
                },
              },
            },
          },
        },
      );
      const owner = await s.user("owner");
      const admin = await s.user("admin");
      const member = await s.user("member");
      const outsider = await s.user("outsider");
      const organization = await s.organization(owner, { admin, member });
      await s.rows(
        "insert into public.bs_test_lifecycle (organization_id, name) values ($1, 'a'), ($1, 'b')",
        [organization],
      );
      const lifecycle = createDataLifecycle({ transport: sqlTransport(s.sql) });
      const disabled = async (): Promise<boolean> => {
        await s.service();
        return s.value<boolean>("better_supabase.tenant_disabled($1)", [
          organization,
        ]);
      };

      await s.asRole(admin);
      const forbidden =
        await lifecycle.requestOrganizationDeletion(organization);
      expect(forbidden.ok ? undefined : forbidden.error.hint).toBe(
        "ORGANIZATION_DELETION_FORBIDDEN",
      );

      await s.asRole(owner);
      const pending = await lifecycle
        .requestOrganizationDeletion(organization, { grace: "P14D" })
        .orThrow();
      expect(
        pending.purgeAfter.epochMilliseconds -
          pending.requestedAt.epochMilliseconds,
      ).toBe(14 * 24 * 3600 * 1000);
      expect(await disabled()).toBe(true);

      await s.asRole(member);
      expect(
        (await lifecycle.organizationDeletion(organization).orThrow())
          ?.organizationId,
      ).toBe(organization);
      const notMine = await lifecycle.cancelOrganizationDeletion(organization);
      expect(notMine.ok ? undefined : notMine.error.hint).toBe(
        "ORGANIZATION_DELETION_FORBIDDEN",
      );
      await s.asRole(outsider);
      expect(await lifecycle.organizationDeletion(organization).orThrow()).toBe(
        undefined,
      );

      await s.service();
      const purger = createOrganizationPurger({
        transport: sqlTransport(s.sql),
      });
      const early = await purger.purge(organization);
      expect(early.ok ? undefined : early.error.hint).toBe(
        "ORGANIZATION_DELETION_NOT_DUE",
      );
      expect(await purger.purgeDue().orThrow()).toEqual([]);

      await s.asRole(owner);
      expect(
        (await lifecycle.cancelOrganizationDeletion(organization).orThrow())
          ?.cancelledAt,
      ).toBeDefined();
      expect(await disabled()).toBe(false);
      await s.asRole(owner);
      expect(
        await lifecycle.cancelOrganizationDeletion(organization).orThrow(),
      ).toBe(undefined);

      await lifecycle
        .requestOrganizationDeletion(organization, { grace: "0 seconds" })
        .orThrow();
      expect(await disabled()).toBe(true);

      const memory = memoryStorage();
      memory.files.set(`${organization}/attachments/a1`, "x");
      memory.files.set(`${organization}/attachments/a2`, "y");
      memory.files.set("other/attachments/a3", "z");
      const cancelled: string[] = [];
      const purging = createOrganizationPurger({
        transport: sqlTransport(s.sql),
        storage: memory.storage,
        buckets: ["attachments"],
        billing: {
          cancelSubscription: (id) =>
            AsyncResult.from(() => {
              cancelled.push(id);
              return Promise.resolve(ok(undefined));
            }),
        },
      });
      await s.service();
      const [purged] = await purging.purgeDue().orThrow();
      expect(purged).toMatchObject({
        organizationId: organization,
        removed: { attachments: 2 },
        deleted: {
          "public.bs_test_lifecycle": 2,
          "better_supabase.memberships": 3,
        },
      });
      expect(cancelled).toEqual([organization]);
      expect([...memory.files.keys()]).toEqual(["other/attachments/a3"]);
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.organizations where id = $1)",
          [organization],
        ),
      ).toBe(0);
      expect(
        await s.value<number>(
          "(select count(*)::int from public.bs_test_purges where organization_id = $1)",
          [organization],
        ),
      ).toBe(1);
      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where type like 'organization.%' and organization_id = $1 order by position",
        [organization],
      );
      expect(events.map((event) => event.type).slice(-4)).toEqual([
        "organization.deletion_requested",
        "organization.deletion_cancelled",
        "organization.deletion_requested",
        "organization.purged",
      ]);
      expect(
        await s.hint("better_supabase.request_organization_deletion($1)", [
          organization,
        ]),
      ).toBe("ORGANIZATION_PURGED");
    } finally {
      await s.close();
    }
  });

  it("finds tenant tables by column, purges past restricting keys and lets platform staff delete", async () => {
    const s = await BlockSession.open(pool);
    const schema = `bs_auto_${crypto.randomUUID().slice(0, 8)}`;
    try {
      await s.rows(
        `create schema ${schema};
         create table ${schema}.projects (
           id uuid primary key default gen_random_uuid(),
           organization_id uuid not null
         );
         create table ${schema}.tasks (
           id uuid primary key default gen_random_uuid(),
           organization_id uuid not null,
           project_id uuid not null references ${schema}.projects (id) on delete restrict
         );
         create table ${schema}.tasks_archive (organization_id uuid not null);`,
      );
      await s.install(["organizations", "data-lifecycle"], {
        modules: {
          "data-lifecycle": {
            options: {
              autoTables: {
                schemas: [schema],
                exclude: [`${schema}.*_archive`],
              },
            },
            permissions: { deletePlatform: "platform.organizations.delete" },
          },
        },
      });
      const owner = await s.user("owner");
      const staff = await s.user("staff");
      const organization = await s.organization(owner);
      const [project] = await s.rows<{ id: string }>(
        `insert into ${schema}.projects (organization_id) values ($1) returning id`,
        [organization],
      );
      await s.rows(
        `insert into ${schema}.tasks (organization_id, project_id) values ($1, $2), ($1, $2)`,
        [organization, project!.id],
      );
      await s.rows(`insert into ${schema}.tasks_archive values ($1)`, [
        organization,
      ]);
      await s.service();
      const tables = await s.rows<{ name: string }>(
        "select name from better_supabase.data_lifecycle_tables() where subject = 'organization' and name like $1 order by name",
        [`${schema}.%`],
      );
      expect(tables.map((row) => row.name)).toEqual([
        `${schema}.projects`,
        `${schema}.tasks`,
      ]);

      const lifecycle = createDataLifecycle({ transport: sqlTransport(s.sql) });
      await s.asRole(staff);
      expect(
        (await lifecycle.requestOrganizationDeletion(organization)).ok,
      ).toBe(false);
      await s.asRole(staff, {
        platform_permissions: ["platform.organizations.delete"],
      });
      await lifecycle
        .requestOrganizationDeletion(organization, { grace: "0 seconds" })
        .orThrow();

      await s.service();
      const purged = await createOrganizationPurger({
        transport: sqlTransport(s.sql),
      })
        .purge(organization)
        .orThrow();
      expect(purged.deleted).toMatchObject({
        [`${schema}.projects`]: 1,
        [`${schema}.tasks`]: 2,
      });
      expect(
        await s.value<number>(
          `(select count(*)::int from ${schema}.tasks_archive)`,
        ),
      ).toBe(1);
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.organizations where id = $1)",
          [organization],
        ),
      ).toBe(0);
    } finally {
      await s.close();
    }
  });

  it("writes CSV exports", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "settings", "data-lifecycle"]);
      const owner = await s.user("owner");
      const organization = await s.organization(owner);
      await s.rows(
        `insert into better_supabase.organization_settings (organization_id, key, value)
         values ($1, 'note', '"=1+1, \\"quoted\\""'::jsonb)`,
        [organization],
      );
      await s.asRole(owner);
      const lifecycle = createDataLifecycle({ transport: sqlTransport(s.sql) });
      const requested = await lifecycle
        .requestExport({ organizationId: organization })
        .orThrow();
      await s.service();
      const memory = memoryStorage();
      const done = await createDataExporter({
        transport: sqlTransport(s.sql),
        storage: memory.storage,
        format: "csv",
      })
        .run(requested.id)
        .orThrow();
      const settings = done.files.find((file) =>
        file.endsWith("organization_settings.csv"),
      );
      expect(settings).toBeDefined();
      const csv = memory.files.get(settings!)!;
      const [header, row] = csv.split("\r\n");
      expect(header!.split(",")).toEqual(
        expect.arrayContaining(["organization_id", "key", "value"]),
      );
      expect(row).toContain(`"'=1+1, ""quoted"""`);
    } finally {
      await s.close();
    }
  });
});
