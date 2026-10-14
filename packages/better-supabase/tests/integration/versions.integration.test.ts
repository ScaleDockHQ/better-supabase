import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { ModuleLayout } from "../../src/sql/module-types.ts";

import {
  createVersions,
  sqlTransport,
} from "../../src/blocks/versions/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const layout: ModuleLayout = {
  subjects: {
    doc: { table: "versions_it.docs", idType: "uuid" },
    note: { table: "versions_it.notes", idType: "uuid" },
  },
  modules: {
    versions: {
      options: {
        keep: 3,
        subjects: {
          doc: {
            columns: ["title", "body"],
            freeze: { column: "status", values: ["sent"] },
          },
          note: { columns: ["text"], auto: true },
        },
      },
    },
  },
};

const TABLES = `create schema versions_it;
create table versions_it.docs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  title text not null,
  body jsonb not null default '{}',
  status text not null default 'draft'
);
create table versions_it.notes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  text text not null
);`;

describe.skipIf(!live)("versions", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("snapshots, diffs, restores, freezes and prunes a subject's versions", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.client.query(TABLES);
      await s.install(["organizations", "versions"], layout);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const stranger = await s.user("stranger");
      const tenant = await s.organization(owner, { member });
      await s.organization(stranger);
      const versions = createVersions({ transport: sqlTransport(s.sql) });
      const docRows = await s.rows<{ id: string }>(
        `insert into versions_it.docs (organization_id, title, body) values ($1, 'Plan', '{"steps": ["a"]}') returning id`,
        [tenant],
      );
      const doc = docRows[0]!.id;
      const input = {
        organizationId: tenant,
        subjectType: "doc",
        subjectId: doc,
      };

      await s.as(member);
      const first = await versions.snapshot(input).orThrow();
      expect(first).toMatchObject({ number: 1, unchanged: false });
      expect(await versions.snapshot(input).orThrow()).toMatchObject({
        id: first.id,
        unchanged: true,
      });

      await s.service();
      await s.client.query(
        `update versions_it.docs set title = 'Plan B', body = '{"steps": ["a", "b"]}' where id = $1`,
        [doc],
      );
      await s.as(member);
      const second = await versions
        .snapshot({ ...input, label: "Second" })
        .orThrow();
      expect(second.number).toBe(2);
      const listed = await versions.list(tenant, "doc", doc).orThrow();
      expect(listed.map((version) => [version.number, version.label])).toEqual([
        [2, "Second"],
        [1, undefined],
      ]);
      expect(await versions.diff(first.id, second.id).orThrow()).toEqual([
        { op: "add", path: "/body/steps/1", value: "b" },
        { op: "replace", path: "/title", value: "Plan B" },
      ]);

      const restored = await versions.restore(first.id).orThrow();
      expect(restored).toMatchObject({ number: 3, restoredFrom: 1 });
      expect(
        await s.value<string>(
          "(select title from versions_it.docs where id = $1)",
          [doc],
        ),
      ).toBe("Plan");
      expect((await versions.get(restored.id).orThrow()).source).toBe(
        "restore",
      );

      await s.service();
      await s.client.query(
        "update versions_it.docs set status = 'sent' where id = $1",
        [doc],
      );
      await s.as(owner);
      const frozen = (await versions.list(tenant, "doc", doc).orThrow())[0]!;
      expect(frozen).toMatchObject({ number: 4, label: "sent", frozen: true });
      expect(
        await versions.delete(frozen.id).then((r) => !r.ok && r.error.hint),
      ).toBe("VERSION_FROZEN");

      await s.as(member);
      expect(
        await versions.delete(second.id).then((r) => !r.ok && r.error.hint),
      ).toBe("VERSION_FORBIDDEN");
      await s.as(stranger);
      expect(
        await versions.get(first.id).then((r) => !r.ok && r.error.hint),
      ).toBe("VERSION_FORBIDDEN");

      await s.as(member);
      for (const title of ["C", "D", "E"]) {
        await versions.snapshot({ ...input, content: { title } }).orThrow();
      }
      const kept = await versions.list(tenant, "doc", doc).orThrow();
      expect(kept.map((version) => version.number)).toEqual([7, 6, 5, 4, 2]);

      await s.service();
      const noteRows = await s.rows<{ id: string }>(
        `insert into versions_it.notes (organization_id, text) values ($1, 'one') returning id`,
        [tenant],
      );
      const note = noteRows[0]!.id;
      await s.client.query(
        "update versions_it.notes set text = 'two' where id = $1",
        [note],
      );
      await s.client.query(
        "update versions_it.notes set text = 'three' where id = $1",
        [note],
      );
      const auto = await versions.list(tenant, "note", note).orThrow();
      expect(auto.map((version) => version.source)).toEqual(["auto"]);
      expect((await versions.get(auto[0]!.id).orThrow()).content).toEqual({
        text: "three",
      });
    } finally {
      await s.close();
    }
  });
});
