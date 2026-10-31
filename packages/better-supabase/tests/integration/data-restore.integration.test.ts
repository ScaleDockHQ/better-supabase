import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type {
  LifecycleStorage,
  RestoreFile,
  StorageEntry,
} from "../../src/blocks/data-lifecycle/index.ts";

import {
  createDataExporter,
  createDataImporter,
  createDataLifecycle,
  sqlTransport,
} from "../../src/blocks/data-lifecycle/index.ts";
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
          if (!path.startsWith(`${prefix}/`)) {
            continue;
          }

          const [name, ...rest] = path.slice(prefix.length + 1).split("/");
          entries.set(name!, {
            name: name!,
            id: rest.length > 0 ? null : path,
          });
        }

        return Promise.resolve({ data: [...entries.values()], error: null });
      },
      remove: (paths) => {
        for (const path of paths) {
          files.delete(path);
        }

        return Promise.resolve({ data: [], error: null });
      },
    }),
  };

  return { files, storage };
}

describe.skipIf(!live)("data restore", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("restores an exported organization into a fresh one, and a second restore writes nothing", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.rows(
        `create table public.bsb_test_restore_orders (
           id uuid primary key default gen_random_uuid(),
           organization_id uuid not null,
           name text not null,
           meta jsonb,
           total numeric(12, 2)
         );
         create table public.bsb_test_restore_lines (
           id uuid primary key default gen_random_uuid(),
           organization_id uuid not null,
           order_id uuid not null references public.bsb_test_restore_orders (id),
           qty integer not null
         );`,
      );
      await s.install(
        [
          "organizations",
          "outbox",
          "settings",
          "comments",
          "queue",
          "imports",
          "data-lifecycle",
        ],
        {
          modules: {
            "data-lifecycle": {
              options: {
                tables: {
                  "public.bsb_test_restore_orders": {
                    tenant: "organization_id",
                  },
                  "public.bsb_test_restore_lines": {
                    tenant: "organization_id",
                  },
                },
              },
            },
          },
        },
      );
      const owner = await s.user("owner");
      const source = await s.organization(owner);
      const target = await s.organization(owner);

      await s.rows(
        `insert into public.bsb_test_restore_orders (organization_id, name, meta, total)
         select $1, 'order ' || g, jsonb_build_object('n', g, 'none', null), g * 10.5 from generate_series(1, 3) g`,
        [source],
      );
      await s.rows(
        `insert into public.bsb_test_restore_lines (organization_id, order_id, qty)
         select $1, o.id, 2 from public.bsb_test_restore_orders o where o.organization_id = $1`,
        [source],
      );

      const count = async (table: string, organization: string) =>
        Number(
          (
            await s.rows<{ n: string }>(
              `select count(*) n from ${table} where organization_id = $1`,
              [organization],
            )
          )[0]!.n,
        );

      await s.asRole(owner);

      const lifecycle = createDataLifecycle({ transport: sqlTransport(s.sql) });

      const request = await lifecycle
        .requestExport({ organizationId: source })
        .orThrow();

      await s.service();
      const memory = memoryStorage();

      await createDataExporter({
        transport: sqlTransport(s.sql),
        storage: memory.storage,
      })
        .run(request.id)
        .orThrow();

      const files: RestoreFile[] = [...memory.files]
        .filter(([path]) => path.includes("bsb_test_restore"))
        .map(([name, body]) => ({ name, text: () => Promise.resolve(body) }));

      expect(files).toHaveLength(2);

      await s.rows(
        "delete from public.bsb_test_restore_lines where organization_id = $1",
        [source],
      );
      await s.rows(
        "delete from public.bsb_test_restore_orders where organization_id = $1",
        [source],
      );

      const importer = createDataImporter({
        transport: sqlTransport(s.sql),
        batchSize: 2,
      });

      const dry = await importer
        .restore({ organizationId: target, files, dryRun: true })
        .orThrow();

      expect(dry.dryRun).toBe(true);
      expect(await count("public.bsb_test_restore_orders", target)).toBe(0);

      const first = await importer
        .restore({ organizationId: target, files })
        .orThrow();

      expect(first.unknownTables).toEqual([]);
      expect(first.tables.flatMap((table) => table.errors)).toEqual([]);
      expect(first.written).toBe(6);
      expect(await count("public.bsb_test_restore_orders", target)).toBe(3);
      expect(await count("public.bsb_test_restore_lines", target)).toBe(3);

      const restored = await s.rows<{ meta: unknown; total: string }>(
        "select meta, total from public.bsb_test_restore_orders where organization_id = $1 and name = 'order 2'",
        [target],
      );

      expect(restored[0]).toMatchObject({
        meta: { n: 2, none: null },
        total: "21.00",
      });

      const audit = await s.rows<{ n: string }>(
        "select count(*) n from better_supabase.outbox_events where type like 'import.%'",
      );

      expect(Number(audit[0]!.n)).toBeGreaterThan(0);

      const second = await importer
        .restore({ organizationId: target, files })
        .orThrow();

      expect(second.written).toBe(0);
      expect(second.tables.map((table) => table.unchanged)).toEqual([3, 3]);
      expect(await count("public.bsb_test_restore_orders", target)).toBe(3);

      const csv = await importer.restore({
        organizationId: target,
        files: [
          {
            name: "public.bsb_test_restore_orders.csv",
            text: () => Promise.resolve(""),
          },
        ],
      });

      expect(csv.error).toMatchObject({ hint: "DATA_RESTORE_CSV" });
    } finally {
      await s.close();
    }
  });

  it("does not overwrite a row that belongs to another organization", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.rows(
        `create table public.bsb_test_restore_orders (
           id uuid primary key default gen_random_uuid(),
           organization_id uuid not null,
           name text not null
         );`,
      );
      await s.install(
        [
          "organizations",
          "outbox",
          "settings",
          "comments",
          "queue",
          "imports",
          "data-lifecycle",
        ],
        {
          modules: {
            "data-lifecycle": {
              options: {
                tables: {
                  "public.bsb_test_restore_orders": {
                    tenant: "organization_id",
                  },
                },
              },
            },
          },
        },
      );
      const owner = await s.user("owner");
      const source = await s.organization(owner);
      const target = await s.organization(owner);

      const [row] = await s.rows<{ id: string }>(
        "insert into public.bsb_test_restore_orders (organization_id, name) values ($1, 'keep') returning id",
        [source],
      );

      await s.service();

      const report = await createDataImporter({
        transport: sqlTransport(s.sql),
      })
        .restore({
          organizationId: target,
          files: [
            {
              name: "public.bsb_test_restore_orders.ndjson",
              text: () =>
                Promise.resolve(
                  `${JSON.stringify({ id: row!.id, organization_id: source, name: "taken" })}\n`,
                ),
            },
          ],
        })
        .orThrow();

      expect(report.written).toBe(0);
      expect(report.tables[0]!.errors[0]!.code).toBe(
        "DATA_RESTORE_ROW_CONFLICT",
      );

      const kept = await s.rows<{ name: string }>(
        "select name from public.bsb_test_restore_orders where id = $1",
        [row!.id],
      );

      expect(kept[0]!.name).toBe("keep");
    } finally {
      await s.close();
    }
  });
});
