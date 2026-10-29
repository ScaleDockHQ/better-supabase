import { describe, expect, it } from "vitest";

import type { AttachmentStorage } from "../../../src/blocks/attachments/attachments.ts";
import type { PreviewRenderer } from "../../../src/blocks/drive/index.ts";

import {
  createDrive,
  createDrivePreviews,
  previewRendererOf,
} from "../../../src/blocks/drive/index.ts";

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

const NODE = {
  id: "n1",
  organizationId: "o",
  parentId: null,
  kind: "file",
  name: "plan.pdf",
  createdAt: "2026-10-01T00:00:00Z",
  attachmentId: "a1",
  file: { mimeType: "application/pdf", size: 10, status: "clean" },
  downloadBlocked: false,
};

const ATTACHMENT = {
  id: "a1",
  organization_id: "o",
  bucket: "files",
  object_path: "o/a1/plan.pdf",
  name: "plan.pdf",
  mime_type: "application/pdf",
  size: 10,
  status: "clean",
  uploaded_at: "2026-10-01T00:00:00Z",
  created_at: "2026-10-01T00:00:00Z",
};

const PREVIEWS = {
  attachmentId: "a1",
  bucket: "files",
  pages: 0,
  prefix: "_previews/o/n1/a1",
  paths: [],
};

describe("drive check-out locks", () => {
  it("locks with an end and a note, and force-unlocks", async () => {
    const fake = transport({
      drive_lock: () => ({
        ...NODE,
        lockedBy: "u1",
        lockedUntil: "2026-10-01T08:00:00Z",
        lockNote: "Editing the budget",
      }),
      drive_unlock: () => ({ ...NODE, lockedBy: null, lockedUntil: null }),
    });

    const drive = createDrive({ transport: fake });

    const locked = await drive
      .lock("n1", {
        until: Temporal.Instant.from("2026-10-01T08:00:00Z"),
        note: "Editing the budget",
      })
      .orThrow();

    expect(locked.lockedBy).toBe("u1");
    expect(locked.lockedUntil?.toString()).toBe("2026-10-01T08:00:00Z");
    expect(locked.lockNote).toBe("Editing the budget");

    const unlocked = await drive.unlock("n1", { force: true }).orThrow();
    expect(unlocked.lockedBy).toBeUndefined();

    expect(fake.calls).toEqual([
      [
        "drive_lock",
        {
          node: "n1",
          until: "2026-10-01T08:00:00Z",
          note: "Editing the budget",
        },
      ],
      ["drive_unlock", { node: "n1", force: true }],
    ]);
  });

  it("defaults the lock end in SQL and unlock without force", async () => {
    const fake = transport({
      drive_lock: () => NODE,
      drive_unlock: () => NODE,
    });

    const drive = createDrive({ transport: fake });

    await drive.lock("n1").orThrow();
    await drive.unlock("n1").orThrow();

    expect(fake.calls).toEqual([
      ["drive_lock", { node: "n1", until: null, note: null }],
      ["drive_unlock", { node: "n1", force: false }],
    ]);
  });
});

describe("drive download blocks", () => {
  it("blocks a node and a drive", async () => {
    const fake = transport({
      drive_set_download_blocked: (args) =>
        (args as { target_type: string }).target_type === "node"
          ? { ...NODE, downloadBlocked: true }
          : {
              id: "d1",
              organizationId: "o",
              name: "Team",
              kind: "shared",
              createdAt: "2026-10-01T00:00:00Z",
              downloadBlocked: true,
            },
    });

    const drive = createDrive({ transport: fake });

    expect((await drive.blockDownloads("n1").orThrow()).downloadBlocked).toBe(
      true,
    );
    expect(
      (await drive.blockDriveDownloads("d1", true).orThrow()).downloadBlocked,
    ).toBe(true);

    expect(fake.calls).toEqual([
      [
        "drive_set_download_blocked",
        { target_type: "node", target_id: "n1", blocked: true },
      ],
      [
        "drive_set_download_blocked",
        { target_type: "drive", target_id: "d1", blocked: true },
      ],
    ]);
  });

  it("refuses a download the node reports as blocked", async () => {
    const fake = transport({
      drive_get: () => ({ ...NODE, downloadable: false }),
    });

    const drive = createDrive({
      transport: fake,
      attachments: {
        download: () => {
          throw new Error("not reached");
        },
      },
    });

    const result = await drive.download("n1");

    expect(result.ok).toBe(false);
    expect(result.ok ? undefined : result.error.hint).toBe(
      "DRIVE_DOWNLOAD_BLOCKED",
    );
  });

  it("reads a link's download flag and previews", async () => {
    const fake = transport({
      drive_link: () => ({
        link: {
          id: "l1",
          role: "view",
          nodeId: "n1",
          expiresAt: null,
          downloadAllowed: false,
        },
        node: NODE,
        children: null,
        object: null,
        previews: { ...PREVIEWS, pages: 1, paths: ["_previews/o/n1/a1/1"] },
      }),
    });

    const view = await createDrive({ transport: fake }).link("t").orThrow();

    expect(view.link.downloadAllowed).toBe(false);
    expect(view.object).toBeUndefined();
    expect(view.previews?.paths).toEqual(["_previews/o/n1/a1/1"]);
  });
});

function storage(files: Record<string, Blob>) {
  const uploads: [string, string, string | undefined][] = [];
  const signed: string[] = [];

  const store: AttachmentStorage = {
    from: (bucket) => ({
      createSignedUploadUrl: () =>
        Promise.resolve({ data: { signedUrl: "", token: "" }, error: null }),
      createSignedUrl: (path) => {
        signed.push(path);

        return Promise.resolve({
          data: { signedUrl: `https://storage.test/${bucket}/${path}` },
          error: null,
        });
      },
      download: (path) => {
        const file = files[path];

        return Promise.resolve(
          file === undefined
            ? { data: null, error: { message: "missing" } }
            : { data: file, error: null },
        );
      },
      remove: () => Promise.resolve({ data: [], error: null }),
      upload: (path, _body, upload) => {
        uploads.push([bucket, path, upload?.contentType]);

        return Promise.resolve({ data: { path }, error: null });
      },
    }),
  };

  return { store, uploads, signed };
}

const RENDERER: PreviewRenderer = {
  apiVersion: 1,
  name: "test",
  render: (_file, input) =>
    input.mimeType === "application/pdf"
      ? [
          { body: new Blob(["1"]), contentType: "image/webp" },
          { body: new Blob(["2"]), contentType: "image/webp" },
          { body: new Blob(["3"]), contentType: "image/webp" },
        ]
      : undefined,
};

describe("drive previews", () => {
  it("checks the renderer's apiVersion and name", () => {
    expect(() =>
      previewRendererOf({ ...RENDERER, apiVersion: 2 } as never),
    ).toThrow(/preview renderer API 2/u);
    expect(() => previewRendererOf({ ...RENDERER, name: "Bad Name" })).toThrow(
      /lowercase/u,
    );
  });

  it("renders pages into the preview folder and records them", async () => {
    const fake = transport({
      drive_get: () => NODE,
      get_attachment: () => ATTACHMENT,
      drive_previews: () => PREVIEWS,
      drive_set_previews: (args) => ({
        ...PREVIEWS,
        pages: (args as { pages: number }).pages,
      }),
    });

    const files = storage({ "o/a1/plan.pdf": new Blob(["pdf"]) });

    const previews = await createDrivePreviews({
      transport: fake,
      storage: files.store,
      renderer: RENDERER,
      maxPages: 2,
    })
      .render("n1")
      .orThrow();

    expect(previews?.pages).toBe(2);
    expect(files.uploads).toEqual([
      ["files", "_previews/o/n1/a1/1", "image/webp"],
      ["files", "_previews/o/n1/a1/2", "image/webp"],
    ]);
    expect(fake.calls.at(-1)).toEqual([
      "drive_set_previews",
      { node: "n1", attachment: "a1", pages: 2 },
    ]);
  });

  it("skips infected files, and unscanned ones with requireClean", async () => {
    for (const [status, requireClean] of [
      ["infected", false],
      ["pending", true],
    ] as const) {
      const fake = transport({
        drive_get: () => NODE,
        get_attachment: () => ({ ...ATTACHMENT, status }),
      });

      const previews = await createDrivePreviews({
        transport: fake,
        storage: storage({}).store,
        renderer: RENDERER,
        requireClean,
      })
        .render("n1")
        .orThrow();

      expect(previews).toBeUndefined();
    }
  });

  it("refuses maxPages below 1", () => {
    expect(() =>
      createDrivePreviews({
        transport: transport({}),
        storage: storage({}).store,
        renderer: RENDERER,
        maxPages: 0,
      }),
    ).toThrow(/maxPages must be 1 or more/u);
  });

  it("skips folders and types the renderer leaves out", async () => {
    const folder = await createDrivePreviews({
      transport: transport({ drive_get: () => ({ ...NODE, kind: "folder" }) }),
      storage: storage({}).store,
      renderer: RENDERER,
    })
      .render("n1")
      .orThrow();

    expect(folder).toBeUndefined();

    const fake = transport({
      drive_get: () => NODE,
      get_attachment: () => ({ ...ATTACHMENT, mime_type: "text/plain" }),
      drive_previews: () => PREVIEWS,
    });

    const text = await createDrivePreviews({
      transport: fake,
      storage: storage({ "o/a1/plan.pdf": new Blob(["text"]) }).store,
      renderer: RENDERER,
    })
      .render("n1")
      .orThrow();

    expect(text).toBeUndefined();
    expect(fake.calls.map(([fn]) => fn)).not.toContain("drive_set_previews");
  });

  it("fails without an uploading storage client, and on a failed upload", async () => {
    const results = {
      drive_get: () => NODE,
      get_attachment: () => ATTACHMENT,
      drive_previews: () => PREVIEWS,
    };

    const files = storage({ "o/a1/plan.pdf": new Blob(["pdf"]) });

    const readOnly: AttachmentStorage = {
      from: () => ({
        createSignedUploadUrl: () =>
          Promise.resolve({ data: { signedUrl: "", token: "" }, error: null }),
        createSignedUrl: () =>
          Promise.resolve({ data: { signedUrl: "" }, error: null }),
        download: () =>
          Promise.resolve({ data: new Blob(["pdf"]), error: null }),
        remove: () => Promise.resolve({ data: [], error: null }),
      }),
    };

    const missing = await createDrivePreviews({
      transport: transport(results),
      storage: readOnly,
      renderer: RENDERER,
    }).render("n1");

    expect(missing.ok ? undefined : missing.error.hint).toBe(
      "DRIVE_STORAGE_CLIENT",
    );

    const failing: AttachmentStorage = {
      from: (bucket) => ({
        ...files.store.from(bucket),
        upload: () =>
          Promise.resolve({ data: null, error: { message: "quota" } }),
      }),
    };

    const failed = await createDrivePreviews({
      transport: transport(results),
      storage: failing,
      renderer: RENDERER,
    }).render("n1");

    expect(failed.ok).toBe(false);
  });

  it("runs as a job and throws so the queue retries", async () => {
    const files = storage({ "o/a1/plan.pdf": new Blob(["pdf"]) });

    const previews = createDrivePreviews({
      transport: transport({
        drive_get: () => NODE,
        get_attachment: () => ATTACHMENT,
        drive_previews: () => PREVIEWS,
        drive_set_previews: () => PREVIEWS,
      }),
      storage: files.store,
      renderer: RENDERER,
    });

    await previews.job({ nodeId: "n1" }, {} as never, undefined as never);

    expect(files.uploads).toHaveLength(3);

    const broken = createDrivePreviews({
      transport: transport({}),
      storage: files.store,
      renderer: RENDERER,
    });

    await expect(
      broken.job({ nodeId: "n1" }, {} as never, undefined as never),
    ).rejects.toThrow(/unexpected drive_get/u);
  });

  it("renders from drive attachment events", async () => {
    const fake = transport({
      drive_get: () => NODE,
      get_attachment: () => ATTACHMENT,
      drive_previews: () => PREVIEWS,
      drive_set_previews: () => PREVIEWS,
    });

    const files = storage({ "o/a1/plan.pdf": new Blob(["pdf"]) });

    await createDrivePreviews({
      transport: fake,
      storage: files.store,
      renderer: RENDERER,
    })
      .sink()
      .send([
        {
          type: "dev.better-supabase.attachment.scanned",
          data: { subjectType: "drive_node", subjectId: "n1" },
        },
        {
          type: "dev.better-supabase.attachment.scanned",
          data: { subjectType: "deal", subjectId: "x" },
        },
      ] as never);

    expect(
      fake.calls.filter(([fn]) => fn === "drive_get").map(([, args]) => args),
    ).toEqual([{ node: "n1" }]);
  });

  it("signs preview URLs for a reader", async () => {
    const fake = transport({
      drive_previews: () => ({
        ...PREVIEWS,
        pages: 2,
        paths: ["_previews/o/n1/a1/1", "_previews/o/n1/a1/2"],
      }),
    });

    const files = storage({});

    const urls = await createDrive({ transport: fake, storage: files.store })
      .previewUrls("n1", { expiresIn: 60 })
      .orThrow();

    expect(urls).toEqual([
      "https://storage.test/files/_previews/o/n1/a1/1",
      "https://storage.test/files/_previews/o/n1/a1/2",
    ]);

    const unsigned = await createDrive({ transport: fake })
      .previewUrls("n1")
      .orThrow()
      .catch((error: unknown) => error);

    expect(unsigned).toBeInstanceOf(Error);

    const refusing: AttachmentStorage = {
      from: (bucket) => ({
        ...files.store.from(bucket),
        createSignedUrl: () =>
          Promise.resolve({ data: null, error: { message: "denied" } }),
      }),
    };

    const denied = await createDrive({
      transport: fake,
      storage: refusing,
    }).previewUrls("n1");

    expect(denied.ok).toBe(false);
  });
});
