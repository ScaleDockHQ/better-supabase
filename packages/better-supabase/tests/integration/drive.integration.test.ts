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

/**
 * Drives create their own tables, so a drives-on install goes into a scratch
 * schema: the seeded `better_supabase.drive_nodes` is the single-tree shape.
 */
const DRIVES_LAYOUT: BlockSqlLayout = {
  subjects: {
    drive_node: {
      table: "drive_it.drive_nodes",
      idType: "uuid",
      tenant: "tenant_id",
      title: "name",
      deletedAt: "deleted_at",
      held: "legal_hold_until",
      permissions: { read: "drive.read", write: "drive.manage" },
    },
  },
  modules: {
    drive: { schema: "drive_it", options: { drives: true } },
    "drive-files": { schema: "drive_it" },
  },
};

interface Node {
  readonly id: string;
  readonly name: string;
  readonly kind: string;
  readonly parentId: string | null;
  readonly role?: string;
}

interface DriveRow {
  readonly id: string;
  readonly name: string;
  readonly kind: string;
  readonly ownerId: string | null;
  readonly connectionId: string | null;
  readonly role?: string;
  readonly readOnly: boolean;
}

interface DriveNodeRow extends Node {
  readonly driveId: string | null;
  readonly source: string | null;
  readonly externalId: string | null;
  readonly externalMetadata: Record<string, unknown> | null;
  readonly held: boolean;
  readonly readOnly: boolean;
}

interface ConnectionRow {
  readonly id: string;
  readonly provider: string;
  readonly name: string;
  readonly status: string;
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
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.drive_nodes where better_supabase.drive_can(id, 'viewer'))",
        ),
      ).toBe(3);
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.drive_nodes)",
        ),
      ).toBe(3);

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

  it("creates drives, shares them, holds subtrees and mirrors connections", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(MODULES, DRIVES_LAYOUT);
      const owner = await s.user("owner");
      const member = await s.user("member");
      const tenant = await s.organization(owner, { member });

      await s.asRole(owner);

      const team = await s.value<DriveRow>(
        "drive_it.drive_create_drive($1, 'Team', 'shared')",
        [tenant],
      );

      expect(team).toMatchObject({
        name: "Team",
        kind: "shared",
        role: "owner",
        readOnly: false,
        connectionId: null,
      });
      expect(
        await s.hint(
          "select drive_it.drive_create_drive($1, 'team', 'shared')",
          [tenant],
        ),
      ).toBe("DRIVE_NAME_CONFLICT");
      expect(
        await s.hint(
          "select drive_it.drive_create_drive($1, 'Personal', 'personal')",
          [tenant],
        ),
      ).toBe("DRIVE_KIND_INVALID");
      expect(
        await s.hint("select drive_it.drive_create_folder($1, null, 'Loose')", [
          tenant,
        ]),
      ).toBe("DRIVE_REQUIRED");
      expect(
        await s.hint(
          "select drive_it.drive_create_folder($1, null, 'Loose', null, null, '00000000-0000-0000-0000-000000000001'::uuid)",
          [tenant],
        ),
      ).toBe("DRIVE_NOT_FOUND");

      const docs = await s.value<DriveNodeRow>(
        "drive_it.drive_create_folder($1, null, 'Docs', null, null, $2)",
        [tenant, team.id],
      );

      expect(docs).toMatchObject({
        name: "Docs",
        driveId: team.id,
        role: "owner",
        held: false,
        readOnly: false,
      });

      const specs = await s.value<DriveNodeRow>(
        "drive_it.drive_create_folder($1, $2, 'Specs')",
        [tenant, docs.id],
      );

      expect(specs.driveId).toBe(team.id);

      const temporary = await s.value<DriveRow>(
        "drive_it.drive_create_drive($1, 'Temporary', 'shared')",
        [tenant],
      );

      expect(
        await s.value<boolean>("drive_it.drive_delete_drive($1)", [
          temporary.id,
        ]),
      ).toBe(true);

      await s.asRole(member);
      expect(
        await s.value<DriveRow[]>("drive_it.drive_list_drives($1)", [tenant]),
      ).toEqual([]);
      expect(await s.hint("select drive_it.drive_get($1)", [docs.id])).toBe(
        "DRIVE_NOT_FOUND",
      );
      expect(
        await s.hint("select drive_it.drive_create_folder($1, $2, 'Notes')", [
          tenant,
          docs.id,
        ]),
      ).toBe("DRIVE_NOT_FOUND");

      await s.asRole(owner);

      const shared = await s.value<{ role: string }>(
        "drive_it.drive_share_drive($1, 'user', $2, 'viewer')",
        [team.id, member.id],
      );

      expect(shared.role).toBe("viewer");

      await s.asRole(member);

      const listed = await s.value<DriveRow[]>(
        "drive_it.drive_list_drives($1)",
        [tenant],
      );

      expect(listed.map((drive) => [drive.name, drive.role])).toEqual([
        ["Team", "viewer"],
      ]);
      expect(
        await s.value<DriveNodeRow>("drive_it.drive_get($1)", [specs.id]),
      ).toMatchObject({ role: "viewer", held: false });
      expect(
        await s.hint("select drive_it.drive_create_folder($1, $2, 'Notes')", [
          tenant,
          docs.id,
        ]),
      ).toBe("DRIVE_FORBIDDEN");
      expect(
        await s.hint(
          "select drive_it.drive_create_folder($1, null, 'Root', null, null, $2)",
          [tenant, team.id],
        ),
      ).toBe("DRIVE_FORBIDDEN");
      expect(
        await s.hint("select drive_it.drive_rename_drive($1, 'Renamed')", [
          team.id,
        ]),
      ).toBe("DRIVE_FORBIDDEN");
      expect(
        await s.hint("select drive_it.drive_delete_drive($1)", [team.id]),
      ).toBe("DRIVE_FORBIDDEN");
      expect(
        await s.hint(
          "select drive_it.drive_share_drive($1, 'user', $2, 'editor')",
          [team.id, member.id],
        ),
      ).toBe("DRIVE_FORBIDDEN");

      await s.asRole(owner);
      expect(
        await s.hint(
          "select drive_it.drive_share_drive($1, 'user', $2, 'viewer')",
          [team.id, "00000000-0000-0000-0000-000000000001"],
        ),
      ).toBe("DRIVE_PRINCIPAL_NOT_FOUND");
      expect(
        await s.hint(
          "select drive_it.drive_share_drive($1, 'user', $2, 'admin')",
          [team.id, member.id],
        ),
      ).toBe("DRIVE_ROLE_UNKNOWN");

      await s.value("drive_it.drive_share_drive($1, 'user', $2, 'editor')", [
        team.id,
        member.id,
      ]);

      await s.asRole(member);

      const notes = await s.value<DriveNodeRow>(
        "drive_it.drive_create_folder($1, $2, 'Notes')",
        [tenant, docs.id],
      );

      expect(notes).toMatchObject({ role: "editor", driveId: team.id });

      const grants = await s.value<{ principalId: string; role: string }[]>(
        "drive_it.drive_grants_for_drive($1)",
        [team.id],
      );

      expect(grants).toEqual([
        expect.objectContaining({ principalId: member.id, role: "editor" }),
      ]);

      await s.asRole(owner);
      expect(
        await s.value<boolean>("drive_it.drive_unshare_drive($1, 'user', $2)", [
          team.id,
          member.id,
        ]),
      ).toBe(true);

      await s.asRole(member);
      expect(
        await s.value<DriveRow[]>("drive_it.drive_list_drives($1)", [tenant]),
      ).toEqual([]);
      expect(await s.hint("select drive_it.drive_get($1)", [docs.id])).toBe(
        "DRIVE_NOT_FOUND",
      );

      await s.asRole(owner);
      expect(
        await s.hint(
          "select drive_it.drive_hold($1, now() - interval '1 hour')",
          [specs.id],
        ),
      ).toBe("DRIVE_HOLD_INVALID");

      const held = await s.value<DriveNodeRow>(
        "drive_it.drive_hold($1, now() + interval '1 day')",
        [specs.id],
      );

      expect(held).toMatchObject({ held: true });

      const parent = await s.value<DriveNodeRow>("drive_it.drive_get($1)", [
        docs.id,
      ]);

      expect(parent.held).toBe(true);
      expect(await s.hint("select drive_it.drive_trash($1)", [docs.id])).toBe(
        "DRIVE_HELD",
      );
      expect(await s.hint("select drive_it.drive_delete($1)", [docs.id])).toBe(
        "DRIVE_HELD",
      );
      expect(
        await s.hint("select drive_it.drive_delete_drive($1)", [team.id]),
      ).toBe("DRIVE_HELD");

      const released = await s.value<DriveNodeRow>(
        "drive_it.drive_release_hold($1)",
        [specs.id],
      );

      expect(released.held).toBe(false);
      expect(
        (await s.value<DriveNodeRow>("drive_it.drive_get($1)", [docs.id])).held,
      ).toBe(false);

      await s.value("drive_it.drive_hold($1, now() + interval '1 day')", [
        docs.id,
      ]);
      expect(
        (await s.value<DriveNodeRow>("drive_it.drive_get($1)", [specs.id]))
          .held,
      ).toBe(true);
      expect(await s.hint("select drive_it.drive_trash($1)", [specs.id])).toBe(
        "DRIVE_HELD",
      );
      expect(await s.hint("select drive_it.drive_delete($1)", [specs.id])).toBe(
        "DRIVE_HELD",
      );
      await s.value("drive_it.drive_release_hold($1)", [docs.id]);
      expect(
        await s.value<DriveRow>("drive_it.drive_rename_drive($1, 'Team A')", [
          team.id,
        ]),
      ).toMatchObject({ name: "Team A", role: "owner" });

      const connection = await s.value<ConnectionRow>(
        "drive_it.drive_connect($1, 'google-drive', 'Work')",
        [tenant],
      );

      expect(connection).toMatchObject({
        provider: "google-drive",
        name: "Work",
        status: "active",
      });
      expect(
        await s.hint(
          "select drive_it.drive_connect($1, 'google-drive', 'work')",
          [tenant],
        ),
      ).toBe("DRIVE_CONNECTION_EXISTS");
      expect(
        await s.hint("select drive_it.drive_connect($1, 'dropbox', 'Home')", [
          tenant,
        ]),
      ).toBe("DRIVE_PROVIDER_INVALID");
      expect(
        await s.value<ConnectionRow[]>("drive_it.drive_list_connections($1)", [
          tenant,
        ]),
      ).toEqual([expect.objectContaining({ id: connection.id, name: "Work" })]);

      const mirror = await s.value<DriveRow>(
        "drive_it.drive_create_drive($1, 'Work Drive', 'shared', null, $2)",
        [tenant, connection.id],
      );

      expect(mirror).toMatchObject({
        connectionId: connection.id,
        ownerId: owner.id,
        readOnly: true,
        role: "owner",
      });
      expect(
        await s.hint(
          "select drive_it.drive_create_folder($1, null, 'Mirror', null, null, $2)",
          [tenant, mirror.id],
        ),
      ).toBe("DRIVE_READ_ONLY");

      await s.service();
      expect(
        await s.hint(
          "select drive_it.drive_sync_batch($1, '[]'::jsonb, 'root')",
          [team.id],
        ),
      ).toBe("DRIVE_NOT_CONNECTED");

      const synced = await s.value<number>(
        "drive_it.drive_sync_batch($1, $2::jsonb, 'root', 'run-1')",
        [
          mirror.id,
          JSON.stringify([
            { externalId: "root", name: "Root", kind: "folder" },
            {
              externalId: "a",
              parentExternalId: "root",
              name: "Archive",
              kind: "folder",
            },
            {
              externalId: "b",
              parentExternalId: "a",
              name: "Brief.pdf",
              kind: "file",
              metadata: { size: 12 },
            },
          ]),
        ],
      );

      expect(synced).toBe(3);

      await s.asRole(owner);

      const roots = await s.value<DriveNodeRow[]>(
        "drive_it.drive_list($1, null, 100, 0, $2)",
        [tenant, mirror.id],
      );

      expect(
        roots.map((node) => [node.name, node.source, node.readOnly]),
      ).toEqual([["Root", "google-drive", true]]);

      const children = await s.value<DriveNodeRow[]>(
        "drive_it.drive_list($1, $2)",
        [tenant, roots[0]!.id],
      );

      expect(children.map((node) => node.name)).toEqual(["Archive"]);
      expect(
        await s.value<DriveNodeRow[]>("drive_it.drive_list($1, $2)", [
          tenant,
          children[0]!.id,
        ]),
      ).toEqual([
        expect.objectContaining({
          name: "Brief.pdf",
          externalId: "b",
          externalMetadata: expect.objectContaining({
            parentExternalId: "a",
            size: 12,
            syncRun: "run-1",
          }),
        }),
      ]);
      expect(
        await s.hint("select drive_it.drive_rename($1, 'Renamed')", [
          children[0]!.id,
        ]),
      ).toBe("DRIVE_READ_ONLY");
      expect(
        await s.hint(
          "select drive_it.drive_hold($1, now() + interval '1 day')",
          [children[0]!.id],
        ),
      ).toBe("DRIVE_READ_ONLY");
      expect(
        await s.hint("select drive_it.drive_trash($1)", [children[0]!.id]),
      ).toBe("DRIVE_READ_ONLY");

      await s.service();

      const renamed = await s.value<number>(
        "drive_it.drive_sync_batch($1, $2::jsonb, 'root', 'run-2')",
        [
          mirror.id,
          JSON.stringify([
            { externalId: "root", name: "Root", kind: "folder" },
            {
              externalId: "a",
              parentExternalId: "root",
              name: "Archive 2",
              kind: "folder",
            },
          ]),
        ],
      );

      expect(renamed).toBe(2);

      const pruned = await s.value<number>(
        "drive_it.drive_sync_batch($1, $2::jsonb, 'root', 'run-2', true)",
        [
          mirror.id,
          JSON.stringify([
            { externalId: "root", name: "Root", kind: "folder" },
            {
              externalId: "a",
              parentExternalId: "root",
              name: "Archive 2",
              kind: "folder",
            },
          ]),
        ],
      );

      expect(pruned).toBe(2);

      const removed = await s.value<number>(
        "drive_it.drive_sync_batch($1, $2::jsonb, 'root', 'run-3')",
        [
          mirror.id,
          JSON.stringify([
            { externalId: "root", name: "Root", kind: "folder" },
            { externalId: "a", removed: true },
          ]),
        ],
      );

      expect(removed).toBe(1);

      await s.asRole(owner);
      expect(
        await s.value<DriveNodeRow[]>(
          "drive_it.drive_list($1, null, 100, 0, $2)",
          [tenant, mirror.id],
        ),
      ).toEqual([expect.objectContaining({ name: "Root" })]);

      await s.service();
      await s.client.query(
        "update drive_it.drive_nodes set legal_hold_until = now() + interval '1 day' where external_id = 'root'",
      );
      await s.asRole(owner);
      expect(
        await s.hint("select drive_it.drive_disconnect($1)", [connection.id]),
      ).toBe("DRIVE_HELD");

      await s.service();
      await s.client.query(
        "update drive_it.drive_nodes set legal_hold_until = null where external_id = 'root'",
      );
      await s.asRole(owner);
      expect(
        await s.value<boolean>("drive_it.drive_disconnect($1)", [
          connection.id,
        ]),
      ).toBe(true);
      expect(
        await s.hint("select drive_it.drive_get_drive($1)", [mirror.id]),
      ).toBe("DRIVE_NOT_FOUND");

      await s.service();
      expect(
        await s.value<number>(
          "(select count(*)::int from drive_it.drive_nodes where drive_id = $1)",
          [mirror.id],
        ),
      ).toBe(0);

      const events = await s.rows<{ type: string }>(
        "select distinct type from better_supabase.outbox_events where organization_id = $1 and type like 'drive.%' order by type",
        [tenant],
      );

      expect(events.map((event) => event.type)).toEqual([
        "drive.connection_created",
        "drive.connection_removed",
        "drive.created",
        "drive.deleted",
        "drive.node_created",
        "drive.node_hold_placed",
        "drive.node_hold_released",
        "drive.node_purged",
        "drive.renamed",
        "drive.shared",
        "drive.unshared",
      ]);
    } finally {
      await s.close();
    }
  });

  it("keeps a trashed batch until its legal hold ends", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(MODULES, DRIVES_LAYOUT);
      const owner = await s.user("owner");
      const tenant = await s.organization(owner);

      await s.asRole(owner);

      const drive = await s.value<DriveRow>(
        "drive_it.drive_create_drive($1, 'Archive', 'shared')",
        [tenant],
      );

      const folder = await s.value<DriveNodeRow>(
        "drive_it.drive_create_folder($1, null, 'Case', null, null, $2)",
        [tenant, drive.id],
      );

      const child = await s.value<DriveNodeRow>(
        "drive_it.drive_create_folder($1, $2, 'File')",
        [tenant, folder.id],
      );

      const batch = await s.value<{
        id: string;
        batchId: string;
        count: number;
      }>("drive_it.drive_trash($1)", [folder.id]);

      expect(batch.count).toBe(2);

      await s.service();
      await s.client.query(
        "update drive_it.drive_nodes set legal_hold_until = now() + interval '1 day' where id = $1",
        [child.id],
      );
      await s.client.query(
        "update better_supabase.trash_items set purge_after = now() - interval '1 day' where batch_id = $1",
        [batch.batchId],
      );

      await s.asRole(owner);
      expect(await s.hint("select drive_it.drive_purge($1)", [batch.id])).toBe(
        "TRASH_HELD",
      );

      await s.service();
      expect(
        await s.value<number>("better_supabase.purge_expired_trash()"),
      ).toBe(0);
      expect(
        await s.value<number>(
          "(select count(*)::int from better_supabase.trash_items where batch_id = $1)",
          [batch.batchId],
        ),
      ).toBe(2);
      expect(
        await s.value<number>(
          "(select count(*)::int from drive_it.drive_nodes where id in ($1, $2))",
          [folder.id, child.id],
        ),
      ).toBe(2);

      await s.client.query(
        "update drive_it.drive_nodes set legal_hold_until = null where id = $1",
        [child.id],
      );

      expect(
        await s.value<number>("better_supabase.purge_expired_trash()"),
      ).toBe(2);
      expect(
        await s.value<number>(
          "(select count(*)::int from drive_it.drive_nodes where id in ($1, $2))",
          [folder.id, child.id],
        ),
      ).toBe(0);

      const events = await s.rows<{ type: string }>(
        "select distinct type from better_supabase.outbox_events where organization_id = $1 and type like 'drive.%' order by type",
        [tenant],
      );

      expect(events.map((event) => event.type)).toEqual([
        "drive.created",
        "drive.node_created",
        "drive.node_purged",
      ]);
    } finally {
      await s.close();
    }
  });
});
