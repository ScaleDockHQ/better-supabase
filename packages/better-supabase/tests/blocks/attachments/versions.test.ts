import { describe, expect, it } from "vitest";

import type { AttachmentStorage } from "../../../src/blocks/attachments/index.ts";

import {
  attachmentsOptimistic,
  createAttachments,
} from "../../../src/blocks/attachments/index.ts";

const row = (overrides: Record<string, unknown> = {}) => ({
  id: "a1",
  organization_id: "org-1",
  subject_type: "task",
  subject_id: "t1",
  bucket: "attachments",
  object_path: "org-1/attachments/a1",
  name: "photo.png",
  mime_type: "image/png",
  size: "2048",
  version: 1,
  width: 800,
  height: 600,
  pages: null,
  status: "clean",
  scan_detail: null,
  uploaded_by: "u1",
  created_at: "2026-10-06T12:00:00Z",
  uploaded_at: "2026-10-06T12:00:05Z",
  scanned_at: "2026-10-06T12:00:09Z",
  ...overrides,
});

const version = (overrides: Record<string, unknown> = {}) => ({
  id: "v1",
  organization_id: "org-1",
  attachment_id: "a1",
  version: 1,
  bucket: "attachments",
  object_path: "org-1/attachments/a1",
  name: "photo-old.png",
  mime_type: "image/png",
  size: "1024",
  width: null,
  height: null,
  pages: 3,
  status: "clean",
  scan_detail: null,
  uploaded_by: "u1",
  uploaded_at: "2026-10-05T12:00:05Z",
  scanned_at: "2026-10-05T12:00:09Z",
  archived_at: "2026-10-06T12:00:00Z",
  ...overrides,
});

function setup(results: Record<string, unknown>) {
  const calls: [string, Record<string, unknown>][] = [];
  const storageCalls: unknown[][] = [];

  const transport = {
    call(_schema: string, fn: string, args: Readonly<Record<string, unknown>>) {
      calls.push([fn, { ...args }]);

      return Promise.resolve(results[fn]);
    },
  };

  const storage = {
    from: (bucket: string) => ({
      createSignedUploadUrl: (path: string) => {
        storageCalls.push(["upload", bucket, path]);

        return Promise.resolve({
          data: { signedUrl: `https://s/upload/${path}`, token: "tok" },
          error: null,
        });
      },
      createSignedUrl: (path: string, ttl: number, options?: unknown) => {
        storageCalls.push(["sign", path, ttl, options]);

        return Promise.resolve({
          data: { signedUrl: `https://s/sign/${path}` },
          error: null,
        });
      },
      download: () => Promise.resolve({ data: new Blob(), error: null }),
      remove: (paths: string[]) => {
        storageCalls.push(["remove", paths]);

        return Promise.resolve({ data: [], error: null });
      },
    }),
    // SAFETY: each reply has the shape the structural type names.
  } as AttachmentStorage;

  const attachments = createAttachments({
    transport,
    storage,
    tenant: "org-1",
  });

  return { attachments, calls, storageCalls };
}

describe("attachment versions", () => {
  it("reads the version and the measured size", async () => {
    const { attachments } = setup({ get_attachment: row() });

    expect(await attachments.get("a1").orThrow()).toMatchObject({
      version: 1,
      width: 800,
      height: 600,
      pages: undefined,
    });

    const old = setup({ get_attachment: row({ version: undefined }) });

    expect((await old.attachments.get("a1").orThrow()).version).toBe(1);
  });

  it("passes width, height and pages on upload", async () => {
    const { attachments, calls } = setup({
      create_attachment: row({ status: "pending", uploaded_at: null }),
    });

    await attachments
      .upload(
        { type: "task", id: "t1" },
        {
          name: "photo.png",
          mimeType: "image/png",
          size: 2048,
          width: 800,
          height: 600,
        },
      )
      .orThrow();

    expect(calls[0]?.[1]).toMatchObject({ width: 800, height: 600 });
  });

  it("replaces a file and signs the new version's path", async () => {
    const { attachments, calls, storageCalls } = setup({
      replace_attachment: row({
        version: 2,
        object_path: "org-1/attachments/a1-v2",
        status: "pending",
        uploaded_at: null,
      }),
    });

    const upload = await attachments
      .replace("a1", {
        name: "photo.png",
        mimeType: "image/png",
        size: 4096,
        pages: 2,
      })
      .orThrow();

    expect(upload.attachment.version).toBe(2);
    expect(upload.signedUrl).toBe("https://s/upload/org-1/attachments/a1-v2");
    expect(calls).toEqual([
      [
        "replace_attachment",
        {
          id: "a1",
          name: "photo.png",
          mime_type: "image/png",
          size: 4096,
          width: undefined,
          height: undefined,
          pages: 2,
        },
      ],
    ]);
    expect(storageCalls).toEqual([
      ["upload", "attachments", "org-1/attachments/a1-v2"],
    ]);
  });

  it("lists, restores and downloads earlier versions", async () => {
    const { attachments, calls, storageCalls } = setup({
      get_attachment: row({
        version: 2,
        object_path: "org-1/attachments/a1-v2",
      }),
      list_attachment_versions: [version()],
      restore_attachment_version: row(),
    });

    const earlier = await attachments.versions("a1").orThrow();

    expect(earlier).toHaveLength(1);
    expect(earlier[0]).toMatchObject({
      attachmentId: "a1",
      version: 1,
      size: 1024,
      width: undefined,
      pages: 3,
    });
    expect(earlier[0]?.archivedAt.toString()).toBe("2026-10-06T12:00:00Z");

    const old = await attachments.download("a1", { version: 1 }).orThrow();

    expect(old.signedUrl).toBe("https://s/sign/org-1/attachments/a1");

    const now = await attachments.download("a1", { version: 2 }).orThrow();

    expect(now.signedUrl).toBe("https://s/sign/org-1/attachments/a1-v2");

    expect(await attachments.download("a1", { version: 7 })).toMatchObject({
      ok: false,
      error: { kind: "not_found", hint: "ATTACHMENT_VERSION_NOT_FOUND" },
    });

    expect((await attachments.restore("a1", 1).orThrow()).version).toBe(1);
    expect(calls.at(-1)).toEqual([
      "restore_attachment_version",
      { id: "a1", version: 1 },
    ]);

    await attachments.remove("a1").orThrow();
    expect(storageCalls.at(-1)).toEqual([
      "remove",
      ["org-1/attachments/a1-v2", "org-1/attachments/a1"],
    ]);
  });

  it("keeps an infected earlier version behind the scan gate", async () => {
    const { attachments } = setup({
      get_attachment: row({ version: 2 }),
      list_attachment_versions: [version({ status: "infected" })],
    });

    expect(await attachments.download("a1", { version: 1 })).toMatchObject({
      ok: false,
      error: { hint: "ATTACHMENT_NOT_SCANNED" },
    });
  });
});

describe("attachment previews", () => {
  it("signs a resized URL per variant", async () => {
    const { attachments, storageCalls } = setup({ get_attachment: row() });

    const images = attachments.images({
      thumb: { width: 160, height: 160, resize: "cover" },
    });

    expect(images.bucket).toMatchObject({ id: "attachments", public: false });
    expect(images.publicUrl("a1")).toMatchObject({
      ok: false,
      error: { hint: "ATTACHMENT_PRIVATE" },
    });

    const url = await images
      .signedUrl("a1", { transform: "thumb", ttl: 60 })
      .orThrow();

    expect(url).toBe("https://s/sign/org-1/attachments/a1");
    expect(storageCalls.at(-1)).toEqual([
      "sign",
      "org-1/attachments/a1",
      60,
      { transform: { width: 160, height: 160, resize: "cover" } },
    ]);

    const attachment = await attachments.get("a1").orThrow();

    await images.signedUrl(attachment).orThrow();
    expect(storageCalls.at(-1)).toEqual([
      "sign",
      "org-1/attachments/a1",
      300,
      undefined,
    ]);

    await images.signedUrl(attachment, { ttl: "hour" }).orThrow();
    expect(storageCalls.at(-1)?.[2]).toBe(3600);
  });

  it("refuses files that are not scanned, not images, or an unknown variant", async () => {
    const pending = setup({ get_attachment: row({ status: "pending" }) });

    expect(await pending.attachments.images().signedUrl("a1")).toMatchObject({
      ok: false,
      error: { hint: "ATTACHMENT_NOT_SCANNED" },
    });

    const pdf = setup({
      get_attachment: row({ mime_type: "application/pdf" }),
    });

    expect(await pdf.attachments.images().signedUrl("a1")).toMatchObject({
      ok: false,
      error: { hint: "ATTACHMENT_NOT_IMAGE" },
    });

    const png = setup({ get_attachment: row() });

    expect(
      await png.attachments
        .images<"thumb">()
        .signedUrl("a1", { transform: "thumb" }),
    ).toMatchObject({ ok: false });
  });
});

describe("attachmentsOptimistic update", () => {
  it("replaces the attachment in place", async () => {
    const { attachments } = setup({ get_attachment: row() });
    const first = await attachments.get("a1").orThrow();
    const replaced = { ...first, version: 2 };

    const other = { ...first, id: "a2" };

    expect(
      attachmentsOptimistic([other, first], {
        type: "update",
        attachment: replaced,
      }),
    ).toEqual([other, replaced]);
    expect(
      attachmentsOptimistic(
        [first],
        // SAFETY: an action outside the union reaches the exhaustive default.
        { type: "unknown" } as unknown as Parameters<
          typeof attachmentsOptimistic
        >[1],
      ),
    ).toEqual({ type: "unknown" });
  });
});
