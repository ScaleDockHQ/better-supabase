import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { ModuleLayout } from "../../src/sql/module-types.ts";

import { driveSubject } from "../../src/blocks/drive/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const layout: ModuleLayout = {
  subjects: {
    drive_node: {
      table: "better_supabase.drive_nodes",
      idType: "uuid",
      tenant: "tenant_id",
      title: "name",
      deletedAt: "deleted_at",
      permissions: { read: "drive.read", write: "drive.manage" },
    },
  },
};

const MODULES = [
  "organizations",
  "outbox",
  "teams",
  "share-links",
  "versions",
  "trash",
  "drive",
];

interface Node {
  readonly id: string;
  readonly name: string;
  readonly kind: string;
  readonly parentId: string | null;
  readonly role?: string;
}

describe.skipIf(!live)("drive", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("inherits grants down the tree and checks them on every write", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(MODULES, layout);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const tenant = await s.organization(owner, { member });

      const node = (sql: string, params: unknown[] = []): Promise<Node> =>
        s.value<Node>(sql, params);

      await s.asRole(owner);

      const projects = await node(
        "better_supabase.drive_create_folder($1, null, 'Projects')",
        [tenant],
      );

      expect(projects).toMatchObject({ kind: "folder", role: "owner" });

      const launch = await node(
        "better_supabase.drive_create_folder($1, $2, 'Launch')",
        [tenant, projects.id],
      );

      expect(launch.parentId).toBe(projects.id);
      expect(
        await s.hint(
          "select better_supabase.drive_create_folder($1, $2, 'launch')",
          [tenant, projects.id],
        ),
      ).toBe("DRIVE_NAME_CONFLICT");

      const renamed = await node(
        "better_supabase.drive_create_folder($1, $2, 'Launch', 'rename')",
        [tenant, projects.id],
      );

      expect(renamed.name).toBe("Launch (2)");

      await s.asRole(owner, { act: { kind: "support" } });
      expect(
        await s.hint(
          "select better_supabase.drive_create_folder($1, null, 'Support')",
          [tenant],
        ),
      ).toBe("ACTOR_READ_ONLY");
      expect(
        await s.hint("select better_supabase.drive_rename($1, 'Support')", [
          launch.id,
        ]),
      ).toBe("ACTOR_READ_ONLY");

      await s.asRole(member);
      expect(
        await s.value<unknown[]>("better_supabase.drive_list($1)", [tenant]),
      ).toEqual([]);
      expect(
        await s.hint("select better_supabase.drive_get($1)", [launch.id]),
      ).toBe("DRIVE_NOT_FOUND");
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.drive_nodes)",
        ),
      ).toBe(0);

      await s.asRole(owner);
      await s.value("better_supabase.drive_share($1, 'user', $2, 'viewer')", [
        projects.id,
        member.id,
      ]);
      await s.asRole(member);
      expect(
        await node("better_supabase.drive_get($1)", [launch.id]),
      ).toMatchObject({ role: "viewer" });

      const shared = await s.value<Node[]>("better_supabase.drive_shared($1)", [
        tenant,
      ]);

      expect(shared.map((entry) => entry.id)).toEqual([projects.id]);
      expect(
        await s.hint(
          "select better_supabase.drive_create_folder($1, $2, 'Notes')",
          [tenant, launch.id],
        ),
      ).toBe("DRIVE_FORBIDDEN");
      expect(
        await s.hint(
          "select better_supabase.drive_share($1, 'user', $2, 'owner')",
          [launch.id, member.id],
        ),
      ).toBe("DRIVE_FORBIDDEN");

      await s.asRole(owner);
      await s.value("better_supabase.drive_share($1, 'user', $2, 'editor')", [
        launch.id,
        member.id,
      ]);
      await s.asRole(member);

      const notes = await node(
        "better_supabase.drive_create_folder($1, $2, 'Notes')",
        [tenant, launch.id],
      );

      expect(notes.role).toBe("editor");

      const grants = await s.value<{ inherited: boolean; role: string }[]>(
        "better_supabase.drive_grants($1)",
        [notes.id],
      );

      expect(grants.map((grant) => [grant.role, grant.inherited])).toEqual(
        expect.arrayContaining([
          ["editor", true],
          ["viewer", true],
        ]),
      );
      expect(
        await s.hint("select better_supabase.drive_move($1, null)", [
          launch.id,
        ]),
      ).toBe("DRIVE_FORBIDDEN");

      await s.asRole(owner);
      expect(
        await s.hint("select better_supabase.drive_move($1, $2)", [
          projects.id,
          notes.id,
        ]),
      ).toBe("DRIVE_MOVE_CYCLE");

      const moved = await node("better_supabase.drive_move($1, $2)", [
        notes.id,
        projects.id,
      ]);

      expect(moved.parentId).toBe(projects.id);

      const path = await s.value<Node[]>("better_supabase.drive_path($1)", [
        notes.id,
      ]);

      expect(path.map((entry) => entry.name)).toEqual(["Projects", "Notes"]);
      await s.asRole(member);
      expect(
        await node("better_supabase.drive_get($1)", [notes.id]),
      ).toMatchObject({ role: "viewer" });

      await s.asRole(owner);
      await s.value("better_supabase.drive_unshare($1, 'user', $2)", [
        projects.id,
        member.id,
      ]);
      await s.asRole(member);
      expect(
        await s.hint("select better_supabase.drive_get($1)", [notes.id]),
      ).toBe("DRIVE_NOT_FOUND");
      expect(
        await node("better_supabase.drive_get($1)", [launch.id]),
      ).toMatchObject({ role: "editor" });

      await s.service();

      const events = await s.rows<{ type: string }>(
        "select distinct type from better_supabase.outbox_events where organization_id = $1 and type like 'drive.%' order by type",
        [tenant],
      );

      expect(events.map((event) => event.type)).toEqual([
        "drive.node_created",
        "drive.node_moved",
        "drive.node_shared",
        "drive.node_unshared",
      ]);
    } finally {
      await s.close();
    }
  });

  it("uploads files with revisions, bins and restores subtrees, and purges", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(MODULES, layout);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const tenant = await s.organization(owner, { member });

      await s.asRole(owner);

      const folder = await s.value<Node>(
        "better_supabase.drive_create_folder($1, null, 'Specs')",
        [tenant],
      );

      const created = await s.value<{
        node: Node;
        attachment: { id: string; bucket: string; object_path: string };
      }>(
        "better_supabase.drive_create_file($1, $2, 'brief.pdf', 'application/pdf', 10)",
        [tenant, folder.id],
      );

      expect(created.node).toMatchObject({ kind: "file", name: "brief.pdf" });
      await s.service();
      await s.client.query(
        "insert into storage.objects (bucket_id, name, owner_id) select bucket, object_path, $2 from better_supabase.attachments where id = $1",
        [created.attachment.id, owner.id],
      );
      await s.asRole(owner);

      const committed = await s.value<{ attachmentId: string | null }>(
        "better_supabase.drive_commit($1, $2)",
        [created.node.id, created.attachment.id],
      );

      expect(committed.attachmentId).toBe(created.attachment.id);

      const second = await s.value<{ attachment: { id: string } }>(
        "better_supabase.drive_create_file($1, $2, 'Brief.pdf', 'application/pdf', 12, 'replace')",
        [tenant, folder.id],
      );

      await s.service();
      await s.client.query(
        "insert into storage.objects (bucket_id, name, owner_id) select bucket, object_path, $2 from better_supabase.attachments where id = $1",
        [second.attachment.id, owner.id],
      );
      await s.asRole(owner);
      await s.value("better_supabase.drive_commit($1, $2)", [
        created.node.id,
        second.attachment.id,
      ]);

      const revisions = await s.value<
        { id: string; attachmentId: string; current: boolean }[]
      >("better_supabase.drive_revisions($1)", [created.node.id]);

      expect(revisions.map((revision) => revision.current)).toEqual([
        true,
        false,
      ]);

      const restored = await s.value<{ attachmentId: string }>(
        "better_supabase.drive_restore_revision($1, $2)",
        [created.node.id, revisions[1]!.id],
      );

      expect(restored.attachmentId).toBe(created.attachment.id);

      await s.asRole(member);
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.attachments where subject_type = 'drive_node')",
        ),
      ).toBe(0);
      expect(
        await s.value<number>(
          "(select count(*)::int from storage.objects where bucket_id = 'attachments')",
        ),
      ).toBe(0);
      await s.asRole(owner);
      await s.value(
        "better_supabase.drive_share($1, 'role', 'member', 'viewer')",
        [folder.id],
      );
      await s.asRole(member);
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.attachments where subject_type = 'drive_node')",
        ),
      ).toBe(2);

      await s.asRole(owner);

      const binned = await s.value<{ count: number }>(
        "better_supabase.drive_trash($1)",
        [folder.id],
      );

      expect(binned.count).toBe(2);
      expect(
        await s.value<unknown[]>("better_supabase.drive_list($1)", [tenant]),
      ).toEqual([]);

      const bin = await s.value<{ id: string; node: Node }[]>(
        "better_supabase.drive_bin($1)",
        [tenant],
      );

      expect(bin.map((item) => item.node.name)).toEqual(["Specs"]);
      await s.value("better_supabase.drive_create_folder($1, null, 'Specs')", [
        tenant,
      ]);
      expect(
        await s.hint("select better_supabase.drive_restore($1)", [bin[0]!.id]),
      ).toBe("DRIVE_NAME_CONFLICT");

      const back = await s.value<{ count: number; node: Node }>(
        "better_supabase.drive_restore($1, 'rename')",
        [bin[0]!.id],
      );

      expect(back).toMatchObject({ count: 2, node: { name: "Specs (2)" } });
      expect(
        await s.value<Node[]>("better_supabase.drive_list($1, $2)", [
          tenant,
          folder.id,
        ]),
      ).toHaveLength(1);

      await s.value("better_supabase.drive_trash($1)", [folder.id]);

      const again = await s.value<{ id: string }[]>(
        "better_supabase.drive_bin($1)",
        [tenant],
      );

      await s.value("better_supabase.drive_purge($1)", [again[0]!.id]);
      await s.service();
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.drive_nodes where id in ($1, $2))",
          [folder.id, created.node.id],
        ),
      ).toBe(0);
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.attachments where subject_type = 'drive_node')",
        ),
      ).toBe(0);

      const purged = await s.value<{ objects: { path: string }[] }>(
        "(select payload from better_supabase.outbox_events where type = 'drive.node_purged' and payload ->> 'subjectId' = $1)",
        [created.node.id],
      );

      expect(purged.objects).toHaveLength(2);
    } finally {
      await s.close();
    }
  });

  it("indexes nodes for search and links them through relations", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install([...MODULES, "search", "relations"], {
        subjects: { drive_node: driveSubject() },
      });
      const owner = await s.user("owner");
      const member = await s.user("member");
      const tenant = await s.organization(owner, { member });

      const search = (q: string): Promise<{ subjectId: string }[]> =>
        s.value("better_supabase.search($1, array['drive_node'])", [q]);

      await s.asRole(owner);

      const specs = await s.value<Node>(
        "better_supabase.drive_create_folder($1, null, 'Launch specs')",
        [tenant],
      );

      const notes = await s.value<Node>(
        "better_supabase.drive_create_folder($1, null, 'Meeting notes')",
        [tenant],
      );

      expect((await search("launch")).map((hit) => hit.subjectId)).toEqual([
        specs.id,
      ]);
      await s.value("better_supabase.drive_rename($1, 'Release specs')", [
        specs.id,
      ]);
      expect(await search("launch")).toEqual([]);
      expect((await search("release")).map((hit) => hit.subjectId)).toEqual([
        specs.id,
      ]);

      await s.value(
        "better_supabase.link($1::uuid, 'relates', 'drive_node', $2::text, 'drive_node', $3::text, null)",
        [tenant, specs.id, notes.id],
      );

      const edges = await s.value<{ subjectId: string }[]>(
        "better_supabase.relations_of($1::uuid, 'drive_node', $2::text, null)",
        [tenant, specs.id],
      );

      expect(edges.map((edge) => edge.subjectId)).toEqual([notes.id]);

      await s.value("better_supabase.drive_trash($1)", [specs.id]);
      expect(await search("release")).toEqual([]);
    } finally {
      await s.close();
    }
  });
});
