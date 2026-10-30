import { describe, expect, it } from "vitest";

import type { AttachmentStorage } from "../../../src/blocks/attachments/attachments.ts";

import { createDrive } from "../../../src/blocks/drive/index.ts";

function transport(results: Record<string, (args: unknown) => unknown>) {
  const calls: [string, unknown][] = [];

  return {
    calls,
    call(_schema: string, fn: string, args: unknown) {
      calls.push([fn, args]);
      const result = results[fn];

      if (!result) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }

      return Promise.resolve(result(args));
    },
  };
}

const ATTACHMENT = {
  id: "a1",
  organization_id: "o",
  bucket: "files",
  object_path: "o/a1/scan.pdf",
  name: "scan.pdf",
  mime_type: "application/pdf",
  size: 4,
  status: "pending",
  created_at: "2026-10-01T00:00:00Z",
};

const NODE = {
  id: "n1",
  organizationId: "o",
  parentId: "f1",
  kind: "file",
  name: "scan.pdf",
  createdAt: "2026-10-01T00:00:00Z",
  attachmentId: "a1",
};

function storage(options: { upload?: boolean; failUpload?: boolean } = {}) {
  const uploads: [string, string, unknown][] = [];

  const store: AttachmentStorage = {
    from: (bucket) => ({
      createSignedUploadUrl: (path) =>
        Promise.resolve({
          data: { signedUrl: `https://s/${bucket}/${path}`, token: "t" },
          error: null,
        }),
      createSignedUrl: () =>
        Promise.resolve({ data: { signedUrl: "" }, error: null }),
      download: () => Promise.resolve({ data: new Blob(), error: null }),
      remove: () => Promise.resolve({ data: null, error: null }),
      ...(options.upload === false
        ? {}
        : {
            upload: (path: string, _body: unknown, init?: unknown) => {
              uploads.push([bucket, path, init]);

              return Promise.resolve(
                options.failUpload
                  ? {
                      data: null,
                      error: { message: "full", statusCode: "507" },
                    }
                  : { data: { path }, error: null },
              );
            },
          }),
    }),
  };

  return { store, uploads };
}

describe("drive contributions", () => {
  it("signs an upload-only create and commits it", async () => {
    const fake = transport({
      drive_create_file: () => ({ id: "n1", attachment: ATTACHMENT }),
      drive_commit: () => ({ id: "n1", attachmentId: "a1", committed: true }),
    });

    const { store } = storage();
    const drive = createDrive({ transport: fake, storage: store });

    const pending = await drive
      .contribute("o", {
        parentId: "f1",
        name: "scan.pdf",
        mimeType: "application/pdf",
        size: 4,
      })
      .orThrow();

    expect(pending).toMatchObject({
      id: "n1",
      signedUrl: "https://s/files/o/a1/scan.pdf",
      token: "t",
    });
    expect(pending.attachment.path).toBe("o/a1/scan.pdf");
    expect(fake.calls[0]).toEqual([
      "drive_create_file",
      {
        tenant: "o",
        parent: "f1",
        name: "scan.pdf",
        mime_type: "application/pdf",
        size: 4,
        conflict: "rename",
        fields: null,
        drive: null,
      },
    ]);

    await expect(
      drive.commitContribution("n1", "a1").orThrow(),
    ).resolves.toEqual({ id: "n1", attachmentId: "a1" });
  });

  it("reads the full result of a caller who can read the folder", async () => {
    const fake = transport({
      drive_create_file: () => ({ node: NODE, attachment: ATTACHMENT }),
      drive_commit: () => NODE,
    });

    const drive = createDrive({ transport: fake, storage: storage().store });

    const pending = await drive
      .contribute("o", {
        parentId: "f1",
        name: "scan.pdf",
        mimeType: "application/pdf",
        size: 4,
      })
      .orThrow();

    expect(pending.id).toBe("n1");
    await expect(
      drive.commitContribution("n1", "a1").orThrow(),
    ).resolves.toEqual({ id: "n1", attachmentId: "a1" });
  });

  it("needs storage to sign the upload", async () => {
    const drive = createDrive({ transport: transport({}) });

    const result = await drive.contribute("o", {
      parentId: "f1",
      name: "scan.pdf",
      mimeType: "application/pdf",
      size: 4,
    });

    expect(result.ok ? undefined : result.error.hint).toBe(
      "DRIVE_STORAGE_CLIENT",
    );
  });
});

describe("drive file requests", () => {
  it("creates an upload link on a folder", async () => {
    const fake = transport({
      drive_request_files: () => ({ id: "l1", token: "secret" }),
    });

    const drive = createDrive({ transport: fake });

    await expect(
      drive
        .createFileRequest("f1", {
          expiresAt: Temporal.Instant.from("2026-11-01T00:00:00Z"),
          maxUses: 5,
          password: "hunter2",
        })
        .orThrow(),
    ).resolves.toEqual({ id: "l1", token: "secret" });
    expect(fake.calls[0]).toEqual([
      "drive_request_files",
      {
        folder: "f1",
        expires_at: "2026-11-01T00:00:00Z",
        max_uses: 5,
        password: "hunter2",
      },
    ]);

    await drive.createFileRequest("f1").orThrow();
    expect(fake.calls[1]?.[1]).toEqual({
      folder: "f1",
      expires_at: null,
      max_uses: null,
      password: null,
    });
  });

  it("uploads through a link and commits", async () => {
    const fake = transport({
      drive_link_upload: () => ({
        nodeId: "n1",
        bucket: "files",
        path: "o/a1/scan.pdf",
        attachment: ATTACHMENT,
      }),
      drive_commit: () => ({ id: "n1", attachmentId: "a1", committed: true }),
    });

    const { store, uploads } = storage();
    const drive = createDrive({ transport: fake, storage: store });
    const file = new Blob(["%PDF"], { type: "application/pdf" });

    await expect(
      drive
        .uploadToRequest("tok", file, { name: "scan.pdf", password: "pw" })
        .orThrow(),
    ).resolves.toEqual({
      passwordRequired: false,
      id: "n1",
      attachmentId: "a1",
    });
    expect(fake.calls[0]).toEqual([
      "drive_link_upload",
      {
        token: "tok",
        name: "scan.pdf",
        mime_type: "application/pdf",
        size: 4,
        password: "pw",
      },
    ]);
    expect(uploads).toEqual([
      [
        "files",
        "o/a1/scan.pdf",
        { contentType: "application/pdf", upsert: false },
      ],
    ]);
  });

  it("defaults the type and reports a missing password", async () => {
    const fake = transport({
      drive_link_upload: () => ({ passwordRequired: true }),
    });

    const drive = createDrive({ transport: fake, storage: storage().store });

    await expect(
      drive
        .uploadToRequest("tok", new Blob(["x"]), { name: "notes" })
        .orThrow(),
    ).resolves.toEqual({ passwordRequired: true });
    expect(fake.calls[0]?.[1]).toMatchObject({
      mime_type: "application/octet-stream",
      password: null,
    });

    await drive
      .uploadToRequest("tok", new Blob(["x"]), {
        name: "notes",
        mimeType: "text/plain",
      })
      .orThrow();
    expect(fake.calls[1]?.[1]).toMatchObject({ mime_type: "text/plain" });
  });

  it("fails without storage, without upload, and on a failed upload", async () => {
    const pending = () =>
      transport({
        drive_link_upload: () => ({ nodeId: "n1", attachment: ATTACHMENT }),
      });

    const file = new Blob(["%PDF"]);

    const none = await createDrive({ transport: pending() }).uploadToRequest(
      "tok",
      file,
      { name: "scan.pdf" },
    );

    expect(none.ok ? undefined : none.error.hint).toBe("DRIVE_STORAGE_CLIENT");

    const noUpload = await createDrive({
      transport: pending(),
      storage: storage({ upload: false }).store,
    }).uploadToRequest("tok", file, { name: "scan.pdf" });

    expect(noUpload.ok ? undefined : noUpload.error.hint).toBe(
      "DRIVE_STORAGE_CLIENT",
    );

    const failed = await createDrive({
      transport: pending(),
      storage: storage({ failUpload: true }).store,
    }).uploadToRequest("tok", file, { name: "scan.pdf" });

    expect(failed.ok).toBe(false);
  });
});
