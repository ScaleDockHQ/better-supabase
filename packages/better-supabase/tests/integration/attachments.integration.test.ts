import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import type { AttachmentStorage } from "../../src/blocks/attachments/index.ts";

import {
  createAttachments,
  createAttachmentScanner,
  sqlTransport,
} from "../../src/blocks/attachments/index.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const BUCKET = "bs-it-attachments";

/** Signs nothing: the test stores objects through SQL as the caller. */
const storage = (files: Map<string, Blob> = new Map()): AttachmentStorage => ({
  from: () => ({
    createSignedUploadUrl: (path) =>
      Promise.resolve({
        data: { signedUrl: `https://storage.test/upload/${path}`, token: "t" },
        error: null,
      }),
    createSignedUrl: (path) =>
      Promise.resolve({
        data: { signedUrl: `https://storage.test/sign/${path}` },
        error: null,
      }),
    download: (path) =>
      Promise.resolve({ data: files.get(path) ?? new Blob([]), error: null }),
    remove: () => Promise.resolve({ data: [], error: null }),
  }),
});

describe.skipIf(!live)("attachments", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  afterAll(() => pool.end());

  it("accepts only expected uploads, hides unscanned files and records scans", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "outbox", "attachments"], {
        modules: {
          attachments: {
            options: {
              bucket: BUCKET,
              allowedMimeTypes: ["image/*", "application/pdf"],
            },
          },
        },
      });
      const owner = await s.user("owner");
      const member = await s.user("member");
      const reader = await s.user("reader");
      const viewer = await s.user("viewer");
      const outsider = await s.user("outsider");
      const organization = await s.organization(owner, {
        member,
        member2: reader,
        viewer,
      });
      expect(
        await s.value<boolean>(
          "exists (select 1 from storage.buckets where id = $1 and not public)",
          [BUCKET],
        ),
      ).toBe(true);

      const attachments = createAttachments({
        transport: sqlTransport(s.sql),
        storage: storage(),
      });

      await s.asRole(viewer);
      const denied = await attachments.upload({
        organizationId: organization,
        name: "plan.pdf",
        mimeType: "application/pdf",
        size: 10,
      });
      expect(denied.ok).toBe(false);

      await s.asRole(member);
      const upload = await attachments
        .upload({
          organizationId: organization,
          name: "plan.pdf",
          mimeType: "application/pdf",
          size: 10,
          subjectType: "project",
          subjectId: "p-1",
        })
        .orThrow();
      const { attachment } = upload;
      expect(attachment).toMatchObject({
        organizationId: organization,
        status: "pending",
        bucket: BUCKET,
        path: `${organization}/attachments/${attachment.id}`,
        uploadedBy: member.id,
      });
      expect(upload.signedUrl).toContain(attachment.path);

      expect(
        await s.hint(
          "insert into better_supabase.attachments (organization_id, name, mime_type, size) values ($1, 'x.exe', 'application/x-msdownload', 1)",
          [organization],
        ),
      ).not.toBe("no error");

      const early = await attachments.confirm(attachment.id);
      expect(early.ok ? undefined : early.error.hint).toBe(
        "ATTACHMENT_NOT_UPLOADED",
      );

      const store = (name: string): Promise<string> =>
        s.hint(
          `insert into storage.objects (bucket_id, name, owner_id, metadata)
           values ($1, $2, auth.uid()::text, '{"size": 2048, "mimetype": "application/pdf"}')`,
          [BUCKET, name],
        );
      expect(
        await store(`${organization}/attachments/${crypto.randomUUID()}`),
      ).not.toBe("no error");
      await s.asRole(owner);
      expect(await store(attachment.path)).not.toBe("no error");
      await s.asRole(member);
      expect(await store(attachment.path)).toBe("no error");

      const confirmed = await attachments.confirm(attachment.id).orThrow();
      expect(confirmed).toMatchObject({ status: "pending", size: 2048 });
      expect(confirmed.uploadedAt).toBeDefined();
      expect(
        (await attachments.confirm(attachment.id).orThrow()).uploadedAt,
      ).toEqual(confirmed.uploadedAt);
      await s.service();
      const events = await s.rows<{ type: string }>(
        "select type from better_supabase.outbox_events where organization_id = $1 order by position",
        [organization],
      );
      expect(events.map((event) => event.type)).toContain(
        "attachment.uploaded",
      );

      const visible = (): Promise<number> =>
        s.value<number>(
          "(select count(*)::int from storage.objects where bucket_id = $1)",
          [BUCKET],
        );
      expect(await visible()).toBe(1);
      await s.asRole(owner);
      expect(await visible()).toBe(1);
      await s.asRole(reader);
      expect(await visible()).toBe(0);
      const notScanned = await attachments.download(attachment.id);
      expect(notScanned.ok ? undefined : notScanned.error.hint).toBe(
        "ATTACHMENT_NOT_SCANNED",
      );
      for (const stranger of [viewer, outsider]) {
        await s.asRole(stranger);
        expect(await visible()).toBe(0);
        expect((await attachments.get(attachment.id)).ok).toBe(false);
        expect(await attachments.list(organization).orThrow()).toEqual([]);
      }

      await s.asRole(member);
      expect(
        await s.hint("better_supabase.set_attachment_status($1, 'clean')", [
          attachment.id,
        ]),
      ).toMatch(/permission denied/);

      await s.service();
      const scanner = createAttachmentScanner({
        transport: sqlTransport(s.sql),
        storage: storage(),
        scan: (file) => ({
          status: file.size === 0 ? "clean" : "infected",
          detail: "eicar",
        }),
      });
      const scanned = await scanner.scan(attachment.id).orThrow();
      expect(scanned).toMatchObject({ status: "clean", scanDetail: "eicar" });
      expect(scanned.scannedAt).toBeDefined();
      expect(await scanner.scan(attachment.id).orThrow()).toEqual(scanned);

      await s.asRole(reader);
      expect(await visible()).toBe(1);
      const download = await attachments.download(attachment.id).orThrow();
      expect(download.signedUrl).toContain(attachment.path);
      expect(
        (
          await attachments
            .list(organization, { type: "project", id: "p-1" })
            .orThrow()
        ).map((row) => row.id),
      ).toEqual([attachment.id]);
      expect(
        await attachments
          .list(organization, { type: "project", id: "p-2" })
          .orThrow(),
      ).toEqual([]);
      expect(await attachments.remove(attachment.id).orThrow()).toBe(false);

      await s.asRole(member);
      expect(await attachments.remove(attachment.id).orThrow()).toBe(true);
      expect((await attachments.get(attachment.id)).ok).toBe(false);
    } finally {
      await s.close();
    }
  });

  it("records failed and infected scans, and serves files at once without requireScan", async () => {
    const s = await BlockSession.open(pool);
    try {
      await s.install(["organizations", "attachments"], {
        modules: {
          attachments: { options: { bucket: BUCKET, requireScan: false } },
        },
      });
      const owner = await s.user("owner");
      const member = await s.user("member");
      const organization = await s.organization(owner, { member });
      const attachments = createAttachments({
        transport: sqlTransport(s.sql),
        storage: storage(),
        requireScan: false,
      });

      await s.asRole(member);
      const { attachment } = await attachments
        .upload({
          organizationId: organization,
          name: "a.txt",
          mimeType: "text/plain",
          size: 3,
        })
        .orThrow();
      await s.rows(
        "insert into storage.objects (bucket_id, name, owner_id, metadata) values ($1, $2, auth.uid()::text, '{}')",
        [BUCKET, attachment.path],
      );
      expect(await attachments.confirm(attachment.id).orThrow()).toMatchObject({
        status: "clean",
        size: 3,
        mimeType: "text/plain",
      });
      expect((await attachments.download(attachment.id)).ok).toBe(true);

      const second = (
        await attachments
          .upload({
            organizationId: organization,
            name: "b.txt",
            mimeType: "text/plain",
            size: 3,
          })
          .orThrow()
      ).attachment;
      await s.service();
      const forced = await s.value<{ status: string }>(
        "better_supabase.set_attachment_status($1, 'infected')",
        [second.id],
      );
      expect(forced.status).toBe("pending");

      await s.rows(
        "update better_supabase.attachments set uploaded_at = now(), status = 'pending' where id = $1",
        [second.id],
      );
      const failing = createAttachmentScanner({
        transport: sqlTransport(s.sql),
        storage: storage(),
        scan: () => {
          throw new Error("scanner offline");
        },
      });
      const failed = await failing.scan(second.id);
      expect(failed.ok ? undefined : failed.error.hint).toBe(
        "ATTACHMENT_SCAN_FAILED",
      );
      expect(
        await s.value<string>(
          "(select status from better_supabase.attachments where id = $1)",
          [second.id],
        ),
      ).toBe("failed");
      await expect(
        failing.job(
          { attachmentId: second.id },
          undefined as never,
          new AbortController().signal,
        ),
      ).rejects.toThrow(/scanner offline/);

      const infected = createAttachmentScanner({
        transport: sqlTransport(s.sql),
        storage: storage(),
        scan: () => ({ status: "infected", detail: "Eicar-Signature" }),
      });
      await infected.sink().send([
        {
          specversion: "1.0",
          id: "e1",
          source: "/test",
          type: "dev.better-supabase.attachment.uploaded",
          data: { attachmentId: second.id },
        },
        {
          specversion: "1.0",
          id: "e2",
          source: "/test",
          type: "dev.better-supabase.comment.created",
          data: { attachmentId: second.id },
        },
      ]);
      await s.asRole(member);
      const blocked = await attachments.download(second.id);
      expect(blocked.ok ? undefined : blocked.error.hint).toBe(
        "ATTACHMENT_NOT_SCANNED",
      );
      expect(
        await s.value<number>(
          "(select count(*)::int from storage.objects where bucket_id = $1)",
          [BUCKET],
        ),
      ).toBe(1);
    } finally {
      await s.close();
    }
  });
});
