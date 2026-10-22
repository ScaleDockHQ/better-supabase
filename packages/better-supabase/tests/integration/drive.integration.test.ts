import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { createApprovals } from "../../src/blocks/approvals/index.ts";
import { createDrive, driveSubject } from "../../src/blocks/drive/index.ts";
import { createTags } from "../../src/blocks/tags/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const layout: BlockSqlLayout = {
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

  it("labels nodes and approves one version of a file", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install([...MODULES, "tags", "notifications", "approvals"], {
        ...layout,
        modules: {
          approvals: {
            options: {
              policies: {
                drive_node: {
                  approve: {
                    steps: [{ approvers: { role: "owner" } }],
                    selfApproval: true,
                  },
                },
              },
            },
          },
        },
      });
      const owner = await s.user("owner");
      const member = await s.user("member");
      const tenant = await s.organization(owner, { member });
      const transport = sqlTransport(s.sql);
      const drive = createDrive({ transport });
      const tags = createTags({ transport, tenant });
      const approvals = createApprovals({ transport, tenant });

      const upload = async (node: string, attachment: string) => {
        await s.service();
        await s.client.query(
          "insert into storage.objects (bucket_id, name, owner_id) select bucket, object_path, $2 from better_supabase.attachments where id = $1",
          [attachment, owner.id],
        );
        await s.asRole(owner);
        await s.value("better_supabase.drive_commit($1, $2)", [
          node,
          attachment,
        ]);
      };

      await s.asRole(owner);

      const created = await s.value<{ node: Node; attachment: { id: string } }>(
        "better_supabase.drive_create_file($1, null, 'brief.pdf', 'application/pdf', 10)",
        [tenant],
      );

      const file = created.node.id;
      await upload(file, created.attachment.id);

      const second = await s.value<{ attachment: { id: string } }>(
        "better_supabase.drive_upload_revision($1, 'application/pdf', 12)",
        [file],
      );

      await upload(file, second.attachment.id);

      await s.as(owner);

      const final = await tags
        .create({ kind: "label", name: "Final" })
        .orThrow();

      const labeled = await drive.label(file, final.id).orThrow();
      expect(labeled.labels?.map((label) => label.name)).toEqual(["Final"]);
      expect(
        (await drive.labeled(tenant, final.id).orThrow()).map(
          (node) => node.id,
        ),
      ).toEqual([file]);

      const request = await drive
        .requestApproval(file, {
          attachmentId: created.attachment.id,
          reason: "Sign off v1",
        })
        .orThrow();

      expect(request).toMatchObject({
        status: "pending",
        attachmentId: created.attachment.id,
        revision: 1,
        current: false,
      });
      expect((await drive.get(file).orThrow()).approval).toBeUndefined();

      await s.asRole(member);
      expect(
        await s.hint("select better_supabase.drive_label($1, $2)", [
          file,
          final.id,
        ]),
      ).toBe("DRIVE_NOT_FOUND");
      expect(
        await s.hint("select better_supabase.tag($1, 'drive_node', $2, $3)", [
          tenant,
          file,
          final.id,
        ]),
      ).toBe("TAG_SUBJECT_FORBIDDEN");
      expect(
        await s.value<unknown[]>(
          "better_supabase.list_approvals($1, null, false, 'drive_node', $2)",
          [tenant, file],
        ),
      ).toEqual([]);

      await s.asRole(owner);
      await s.value("better_supabase.drive_share($1, 'user', $2, 'viewer')", [
        file,
        member.id,
      ]);
      await s.asRole(member);
      expect(
        (
          await s.value<Node & { labels: { name: string }[] }>(
            "better_supabase.drive_get($1)",
            [file],
          )
        ).labels.map((label) => label.name),
      ).toEqual(["Final"]);
      expect(
        await s.hint("select better_supabase.drive_request_approval($1)", [
          file,
        ]),
      ).toBe("DRIVE_FORBIDDEN");

      await s.as(owner);
      await approvals.approve(request.id).orThrow();

      const [decided] = await drive.approvals(file).orThrow();
      expect(decided).toMatchObject({ status: "approved", current: false });

      const revisions = await drive.revisions(file).orThrow();

      const restored = await drive
        .restoreRevision(
          file,
          revisions.find((revision) => revision.number === 1)!.id,
        )
        .orThrow();

      expect(restored.approval?.status).toBe("approved");

      await s.value("better_supabase.drive_delete($1)", [file]);
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.taggings where subject_id = $1)",
          [file],
        ),
      ).toBe(0);
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
