import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { createApprovals } from "../../src/blocks/approvals/index.ts";
import { createDrive } from "../../src/blocks/drive/index.ts";
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
  modules: {
    drive: {
      options: {
        control: {
          types: ["sop", { name: "policy", numberFormat: "POL-{n:3}" }],
        },
      },
    },
    approvals: {
      options: {
        policies: {
          drive_node: {
            release: { steps: [{ approvers: { role: "admin" }, required: 2 }] },
          },
        },
      },
    },
    acknowledgements: { on: { drive_node: {} } },
  },
};

const MODULES = [
  "organizations",
  "outbox",
  "teams",
  "share-links",
  "versions",
  "trash",
  "notifications",
  "numbering",
  "state-machine",
  "relations",
  "approvals",
  "acknowledgements",
  "drive",
];

interface Attachment {
  readonly id: string;
  readonly bucket: string;
  readonly object_path: string;
}

describe.skipIf(!live)("drive controlled documents", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("releases versions through two approvers and reviews them", async () => {
    const s = await BlockSession.open(pool);

    try {
      await s.install(MODULES, layout);
      const owner = await s.user("owner");
      const first = await s.user("first");
      const second = await s.user("second");
      const reader = await s.user("reader");

      const tenant = await s.organization(owner, {
        admin1: first,
        admin2: second,
        member: reader,
      });

      const transport = sqlTransport(s.sql);
      const drive = createDrive({ transport });
      const approvals = createApprovals({ transport, tenant });

      const upload = async (node: string, attachment: string) => {
        await s.service();
        await s.client.query(
          "insert into storage.objects (bucket_id, name, owner_id) select bucket, object_path, $2 from better_supabase.attachments where id = $1",
          [attachment, owner.id],
        );
        await s.as(owner);
        await drive.commit(node, attachment).orThrow();
      };

      const readable = async (attachment: Attachment) => {
        await s.asRole(reader);

        const allowed = await s.value<boolean>(
          "better_supabase.drive_object_allowed($1, $2, 'select')",
          [attachment.bucket, attachment.object_path],
        );

        await s.as(owner);

        return allowed;
      };

      const pendingRelease = async (): Promise<string> => {
        await s.asRole(owner);

        const requests = await s.value<
          { id: string; action: string; status: string }[]
        >("better_supabase.list_approvals($1, null, false, 'drive_node', $2)", [
          tenant,
          file,
        ]);

        await s.as(owner);

        const pending = requests.find(
          (request) =>
            request.action === "release" && request.status === "pending",
        );

        expect(pending).toBeDefined();

        return pending!.id;
      };

      const approveRelease = async () => {
        const pending = await pendingRelease();
        await s.as(first);
        await approvals.approve(pending).orThrow();
        await s.as(second);
        await approvals.approve(pending).orThrow();
        await s.as(owner);
      };

      await s.asRole(owner);

      const created = await s.value<{
        node: { id: string };
        attachment: Attachment;
      }>(
        "better_supabase.drive_create_file($1, null, 'Cleaning.pdf', 'application/pdf', 10)",
        [tenant],
      );

      const file = created.node.id;
      await upload(file, created.attachment.id);
      await s.asRole(owner);
      await s.value("better_supabase.drive_share($1, 'user', $2, 'viewer')", [
        file,
        reader.id,
      ]);

      await s.as(owner);
      expect(
        (await drive.saveDocument(file, { type: "form" })).error?.hint,
      ).toBe("DRIVE_DOCUMENT_TYPE_UNKNOWN");

      const saved = await drive.saveDocument(file, { type: "sop" }).orThrow();

      expect(saved.document).toMatchObject({
        number: "DOC-00001",
        type: "sop",
        status: "draft",
        ownerId: owner.id,
        effectiveOnly: false,
      });

      await s.asRole(owner);

      const policy = await s.value<{ node: { id: string } }>(
        "better_supabase.drive_create_file($1, null, 'Policy.pdf', 'application/pdf', 10)",
        [tenant],
      );

      await s.as(owner);
      expect(
        (await drive.saveDocument(policy.node.id, { type: "policy" }).orThrow())
          .document?.number,
      ).toBe("POL-001");

      await s.asRole(reader);
      expect(
        await s.value<{ document: { effectiveOnly: boolean } }>(
          "better_supabase.drive_get($1)",
          [file],
        ),
      ).toMatchObject({ document: { effectiveOnly: true } });
      expect(
        await s.hint("select better_supabase.drive_document_submit($1)", [
          file,
        ]),
      ).toBe("DRIVE_FORBIDDEN");
      expect(await readable(created.attachment)).toBe(false);

      const submitted = await drive
        .submitDocument(file, { reason: "First issue" })
        .orThrow();

      expect(submitted.document?.status).toBe("in_review");
      expect((await drive.submitDocument(file)).error?.hint).toBe(
        "DRIVE_DOCUMENT_STATUS_INVALID",
      );
      expect(
        (await drive.releaseDocument(file, created.attachment.id)).error?.hint,
      ).toBe("DRIVE_FORBIDDEN");

      const pending = await pendingRelease();
      await s.as(first);
      await approvals.approve(pending).orThrow();
      await s.as(owner);
      expect((await drive.get(file).orThrow()).document?.status).toBe(
        "in_review",
      );
      await s.as(second);
      await approvals.approve(pending).orThrow();
      await s.as(owner);

      const released = (await drive.get(file).orThrow()).document;

      expect(released).toMatchObject({
        status: "effective",
        effectiveVersion: 1,
        effectiveAttachmentId: created.attachment.id,
        reviewDue: false,
      });
      expect(released?.nextReviewOn).toBeDefined();
      expect(await readable(created.attachment)).toBe(true);

      await s.asRole(owner);
      await s.value(
        "better_supabase.assign_acknowledgement($1, 'drive_node', $2, 'user', $3)",
        [tenant, file, reader.id],
      );
      await s.asRole(reader);

      const mine = await s.value<{ versionId: string }[]>(
        "better_supabase.list_my_acknowledgements($1)",
        [tenant],
      );

      expect(mine.map((each) => each.versionId)).toEqual([
        released?.effectiveVersionId,
      ]);
      await s.value("better_supabase.acknowledge('drive_node', $1)", [file]);
      expect(
        await s.value<unknown[]>(
          "better_supabase.list_my_acknowledgements($1)",
          [tenant],
        ),
      ).toEqual([]);

      await s.asRole(owner);

      const revision = await s.value<{ attachment: Attachment }>(
        "better_supabase.drive_upload_revision($1, 'application/pdf', 12)",
        [file],
      );

      await upload(file, revision.attachment.id);
      expect(await readable(revision.attachment)).toBe(false);
      expect(await readable(created.attachment)).toBe(true);

      await s.service();
      await s.client.query(
        "update better_supabase.drive_nodes set next_review_on = current_date - 1 where id = $1",
        [file],
      );
      await s.as(owner);
      expect(
        (await drive.documents(tenant, { reviewDue: true }).orThrow()).map(
          (node) => node.id,
        ),
      ).toEqual([file]);
      expect(
        await drive
          .documents(tenant, { search: "doc-0000", type: "sop" })
          .orThrow(),
      ).toHaveLength(1);
      expect(
        await s.hint("select better_supabase.drive_documents($1, '[]')", [
          tenant,
        ]),
      ).toBe("DRIVE_DOCUMENT_FILTER_INVALID");
      await s.service();
      expect(await drive.notifyDueReviews().orThrow()).toBe(1);
      expect(await drive.notifyDueReviews().orThrow()).toBe(0);
      await s.as(owner);

      const revise = await drive
        .reviewDocument(file, "revise", "Steps changed")
        .orThrow();

      expect(revise.document?.status).toBe("effective");

      const resubmitted = await drive
        .submitDocument(file, { attachmentId: revision.attachment.id })
        .orThrow();

      expect(resubmitted.document?.status).toBe("effective");
      await approveRelease();

      const current = (await drive.get(file).orThrow()).document;

      expect(current).toMatchObject({
        status: "effective",
        effectiveVersion: 2,
        effectiveAttachmentId: revision.attachment.id,
        reviewDue: false,
      });
      expect(await readable(revision.attachment)).toBe(true);
      expect(await readable(created.attachment)).toBe(false);
      expect(
        await s.value<string[]>(
          "(select array_agg(label order by number) from better_supabase.versions where subject_type = 'drive_node' and subject_id = $1::text)",
          [file],
        ),
      ).toEqual(["superseded", "effective"]);

      await s.asRole(reader);
      expect(
        await s.value<unknown[]>(
          "better_supabase.list_my_acknowledgements($1)",
          [tenant],
        ),
      ).toHaveLength(1);

      await s.as(owner);

      const obsolete = await drive
        .obsoleteDocument(file, "Replaced by DOC-00002")
        .orThrow();

      expect(obsolete.document?.status).toBe("obsolete");
      expect(
        (await drive.saveDocument(file, { type: "sop" })).error?.hint,
      ).toBe("DRIVE_DOCUMENT_STATUS_INVALID");
      expect(
        await drive.documents(tenant, { status: "obsolete" }).orThrow(),
      ).toHaveLength(1);
    } finally {
      await s.close();
    }
  });
});
