import { describe, expect, it } from "vitest";

import { createAttachments } from "../../../src/blocks/attachments/attachments.ts";
import {
  createDrive,
  driveSubject,
  type DriveNode,
} from "../../../src/blocks/drive/index.ts";

function transport(results: Record<string, (args: unknown) => unknown>) {
  const calls: [string, string, unknown][] = [];
  return {
    calls,
    call(schema: string, fn: string, args: unknown) {
      calls.push([schema, fn, args]);
      const result = results[fn];
      if (!result) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }
      return Promise.resolve(result(args));
    },
  };
}

const FOLDER = {
  id: "f1",
  organizationId: "o",
  parentId: null,
  kind: "folder",
  name: "Projects",
  rank: "a0",
  createdBy: "u1",
  createdAt: "2026-10-01T00:00:00Z",
  updatedAt: "2026-10-01T00:00:00Z",
  deletedAt: null,
  role: "owner",
};

const FILE = {
  ...FOLDER,
  id: "n1",
  parentId: "f1",
  kind: "file",
  name: "plan.pdf",
  rank: null,
  createdBy: null,
  updatedAt: null,
  role: undefined,
  attachmentId: "a1",
  file: {
    mimeType: "application/pdf",
    size: 10,
    status: "clean",
    uploadedAt: "2026-10-01T00:00:01Z",
  },
  fields: { drive_id: "d1" },
};

const ATTACHMENT = {
  id: "a2",
  organization_id: "o",
  subject_type: "drive_node",
  subject_id: "n1",
  bucket: "attachments",
  object_path: "o/attachments/a2",
  name: "plan.pdf",
  mime_type: "application/pdf",
  size: 12,
  status: "pending",
  scan_detail: null,
  metadata: {},
  uploaded_by: "u1",
  created_at: "2026-10-02T00:00:00Z",
  uploaded_at: null,
  scanned_at: null,
};

const GRANT = {
  id: "g1",
  nodeId: "f1",
  principalType: "team",
  principalId: "t1",
  role: "editor",
  expiresAt: "2026-11-01T00:00:00Z",
  inherited: true,
};

interface Bucket {
  readonly name: string;
  readonly removed: string[][];
}

function storage(fail?: "url" | "remove") {
  const buckets: Bucket[] = [];
  return {
    buckets,
    from(name: string) {
      const bucket: Bucket = { name, removed: [] };
      buckets.push(bucket);
      return {
        createSignedUploadUrl: (path: string) =>
          Promise.resolve(
            fail === "url"
              ? { data: null, error: { message: "denied", statusCode: "403" } }
              : {
                  data: { signedUrl: `https://up/${path}`, token: "tok" },
                  error: null,
                },
          ),
        createSignedUrl: (path: string) =>
          Promise.resolve({
            data: { signedUrl: `https://down/${path}` },
            error: null,
          }),
        download: () => Promise.resolve({ data: new Blob(["x"]), error: null }),
        remove: (paths: string[]) => {
          bucket.removed.push(paths);
          return Promise.resolve(
            fail === "remove"
              ? { data: null, error: { message: "gone", statusCode: "500" } }
              : { data: paths, error: null },
          );
        },
      };
    },
  };
}

describe("drive client", () => {
  it("creates, lists, moves, renames and shares nodes", async () => {
    const fake = transport({
      drive_create_folder: () => FOLDER,
      drive_get: () => FILE,
      drive_list: () => [FOLDER, FILE],
      drive_shared: () => [FILE],
      drive_path: () => [{ id: "f1", name: "Projects", kind: "folder" }],
      drive_rename: () => ({ ...FILE, name: "plan (2).pdf" }),
      drive_move: () => ({ ...FILE, parentId: null }),
      drive_delete: () => true,
      drive_share: () => ({ ...GRANT, inherited: false, expiresAt: null }),
      drive_unshare: () => true,
      drive_grants: () => [GRANT],
    });
    const drive = createDrive({ transport: fake, schema: "app" });
    const folder = await drive
      .createFolder("o", { name: "Projects", conflict: "rename" })
      .orThrow();
    expect(folder).toMatchObject({
      id: "f1",
      parentId: null,
      kind: "folder",
      rank: "a0",
      role: "owner",
      attachmentId: undefined,
      file: undefined,
      fields: {},
    });
    const file = await drive.get("n1").orThrow();
    expect(file.file?.mimeType).toBe("application/pdf");
    expect(file.file?.uploadedAt?.toString()).toBe("2026-10-01T00:00:01Z");
    expect(file.fields).toEqual({ drive_id: "d1" });
    expect(file.createdBy).toBeUndefined();
    expect(
      (
        await drive
          .list("o", { parentId: "f1", pageSize: 5, skip: 5 })
          .orThrow()
      ).length,
    ).toBe(2);
    expect(await drive.shared("o").orThrow()).toHaveLength(1);
    expect(await drive.path("n1").orThrow()).toEqual([
      { id: "f1", name: "Projects", kind: "folder" },
    ]);
    expect((await drive.rename("n1", "plan.pdf").orThrow()).name).toBe(
      "plan (2).pdf",
    );
    expect(
      (await drive.move("n1", null, { rank: "a1", conflict: "fail" }).orThrow())
        .parentId,
    ).toBeNull();
    expect(await drive.delete("n1").orThrow()).toBe(true);
    const shared = await drive
      .share("f1", { type: "team", id: "t1" }, "editor", {
        expiresAt: Temporal.Instant.from("2026-11-01T00:00:00Z"),
      })
      .orThrow();
    expect(shared).toMatchObject({
      principal: { type: "team", id: "t1" },
      inherited: false,
      expiresAt: undefined,
    });
    expect(
      await drive.unshare("f1", { type: "team", id: "t1" }).orThrow(),
    ).toBe(true);
    const [grant] = await drive.grants("n1").orThrow();
    expect(grant?.inherited).toBe(true);
    expect(grant?.expiresAt?.toString()).toBe("2026-11-01T00:00:00Z");

    expect(fake.calls.map(([schema]) => schema)).toEqual(
      fake.calls.map(() => "app"),
    );
    expect(fake.calls.find(([, fn]) => fn === "drive_list")?.[2]).toEqual({
      tenant: "o",
      parent: "f1",
      page_size: 5,
      skip: 5,
    });
    expect(fake.calls.find(([, fn]) => fn === "drive_move")?.[2]).toEqual({
      node: "n1",
      parent: null,
      rank: "a1",
      conflict: "fail",
    });
    expect(fake.calls.find(([, fn]) => fn === "drive_share")?.[2]).toEqual({
      node: "f1",
      principal_type: "team",
      principal_id: "t1",
      role: "editor",
      expires_at: "2026-11-01T00:00:00Z",
    });
  });

  it("uploads, commits and downloads files through storage", async () => {
    const fake = transport({
      drive_create_file: () => ({ node: FILE, attachment: ATTACHMENT }),
      drive_upload_revision: () => ({ node: FILE, attachment: ATTACHMENT }),
      drive_commit: () => ({ ...FILE, attachmentId: "a2" }),
      drive_get: () => FILE,
      get_attachment: () => ({ ...ATTACHMENT, id: "a1", status: "clean" }),
    });
    const files = storage();
    const drive = createDrive({
      transport: fake,
      storage: files,
      attachments: createAttachments({ transport: fake, storage: files }),
    });
    const upload = await drive
      .upload("o", {
        parentId: "f1",
        name: "plan.pdf",
        mimeType: "application/pdf",
        size: 12,
      })
      .orThrow();
    expect(upload.signedUrl).toBe("https://up/o/attachments/a2");
    expect(upload.token).toBe("tok");
    expect(upload.attachment.path).toBe("o/attachments/a2");
    const revision = await drive
      .uploadRevision("n1", { mimeType: "application/pdf", size: 12 })
      .orThrow();
    expect(revision.node.id).toBe("n1");
    expect((await drive.commit("n1", "a2").orThrow()).attachmentId).toBe("a2");
    const download = await drive.download("n1", { as: "plan.pdf" }).orThrow();
    expect(download.signedUrl).toBe("https://down/o/attachments/a2");
    expect(fake.calls[0]?.[0]).toBe("better_supabase");
  });

  it("refuses file calls without storage and a download of a folder", async () => {
    const fake = transport({ drive_get: () => FOLDER });
    const drive = createDrive({ transport: fake });
    const upload = await drive.upload("o", {
      name: "a.txt",
      mimeType: "text/plain",
      size: 1,
    });
    expect(!upload.ok && upload.error.hint).toBe("DRIVE_STORAGE_CLIENT");
    expect(fake.calls).toEqual([]);
    const download = await drive.download("f1");
    expect(!download.ok && download.error.hint).toBe(
      "DRIVE_ATTACHMENTS_CLIENT",
    );

    const files = storage();
    const withStorage = createDrive({
      transport: fake,
      storage: files,
      attachments: createAttachments({
        transport: fake,
        storage: files,
        schema: "files",
        requireScan: false,
        downloadTtl: 60,
      }),
      mappers: [],
    });
    const folder = await withStorage.download("f1");
    expect(!folder.ok && folder.error.hint).toBe("DRIVE_NOT_A_FILE");
  });

  it("returns the storage error when the upload URL is refused", async () => {
    const fake = transport({
      drive_create_file: () => ({ node: FILE, attachment: ATTACHMENT }),
    });
    const drive = createDrive({ transport: fake, storage: storage("url") });
    const upload = await drive.upload("o", {
      name: "plan.pdf",
      mimeType: "application/pdf",
      size: 12,
    });
    expect(upload.ok).toBe(false);
  });

  it("keeps revisions, a bin, stars, recent items and links", async () => {
    const fake = transport({
      drive_revisions: () => [
        {
          id: "v2",
          number: 2,
          label: null,
          source: "manual",
          attachmentId: "a2",
          name: "plan.pdf",
          mimeType: "application/pdf",
          size: "12",
          current: true,
          createdBy: "u1",
          createdAt: "2026-10-02T00:00:00Z",
        },
      ],
      drive_restore_revision: () => FILE,
      drive_trash: () => ({ id: "t1", batchId: "b1", count: 2 }),
      drive_restore: () => ({
        id: "t1",
        batchId: "b1",
        count: 2,
        node: FOLDER,
      }),
      drive_bin: () => [
        {
          id: "t1",
          batchId: "b1",
          count: 2,
          trashedBy: "u1",
          trashedAt: "2026-10-03T00:00:00Z",
          purgeAfter: null,
          node: { ...FOLDER, deletedAt: "2026-10-03T00:00:00Z" },
        },
      ],
      drive_purge: () => 2,
      drive_star: (args) => (args as { starred: boolean }).starred,
      drive_open: () => FILE,
      drive_marked: (args) => [
        {
          ...FILE,
          starredAt: (args as { recent: boolean }).recent
            ? null
            : "2026-10-04T00:00:00Z",
          openedAt: "2026-10-05T00:00:00Z",
        },
      ],
      drive_link: (args) => ({
        link: {
          id: "l1",
          role: "viewer",
          nodeId: "f1",
          expiresAt: null,
        },
        node: (args as { node: string | null }).node === null ? FOLDER : FILE,
        children:
          (args as { node: string | null }).node === null ? [FILE] : null,
        object:
          (args as { node: string | null }).node === null
            ? null
            : {
                bucket: "attachments",
                path: "o/attachments/a1",
                mimeType: "application/pdf",
                status: "clean",
              },
      }),
    });
    const drive = createDrive({ transport: fake });
    const [revision] = await drive.revisions("n1").orThrow();
    expect(revision).toMatchObject({ number: 2, size: 12, current: true });
    expect(revision?.label).toBeUndefined();
    expect((await drive.restoreRevision("n1", "v1").orThrow()).id).toBe("n1");
    expect(await drive.trash("f1").orThrow()).toEqual({
      id: "t1",
      batchId: "b1",
      count: 2,
    });
    expect(
      (await drive.restore("t1", { conflict: "rename" }).orThrow()).node.id,
    ).toBe("f1");
    const [entry] = await drive
      .bin("o", {
        pageSize: 10,
        before: Temporal.Instant.from("2026-10-04T00:00:00Z"),
      })
      .orThrow();
    expect(entry?.node.deletedAt?.toString()).toBe("2026-10-03T00:00:00Z");
    expect(entry?.purgeAfter).toBeUndefined();
    expect(await drive.purge("t1").orThrow()).toBe(2);
    expect(await drive.star("n1").orThrow()).toBe(true);
    expect(await drive.star("n1", false).orThrow()).toBe(false);
    expect((await drive.open("n1").orThrow()).id).toBe("n1");
    const [starred] = await drive.starred("o").orThrow();
    expect(starred?.starredAt?.toString()).toBe("2026-10-04T00:00:00Z");
    const [recent] = await drive.recent("o", { pageSize: 3 }).orThrow();
    expect(recent?.starredAt).toBeUndefined();
    expect(recent?.openedAt?.toString()).toBe("2026-10-05T00:00:00Z");
    const folder = await drive.link("token").orThrow();
    expect(folder.children?.map((node: DriveNode) => node.id)).toEqual(["n1"]);
    expect(folder.object).toBeUndefined();
    const file = await drive.link("token", { nodeId: "n1" }).orThrow();
    expect(file.children).toBeUndefined();
    expect(file.object?.path).toBe("o/attachments/a1");
  });

  it("prunes and removes the objects per bucket", async () => {
    const objects = [
      { bucket: "attachments", path: "o/1" },
      { bucket: "attachments", path: "o/2" },
      { bucket: "archive", path: "o/3" },
    ];
    const fake = transport({ drive_prune: () => objects });
    const files = storage();
    const drive = createDrive({
      transport: fake,
      storage: files,
      attachments: createAttachments({ transport: fake, storage: files }),
    });
    expect(await drive.prune({ maxObjects: 10 }).orThrow()).toEqual(objects);
    expect(
      files.buckets.map((bucket) => [bucket.name, bucket.removed]),
    ).toEqual([
      ["attachments", [["o/1", "o/2"]]],
      ["archive", [["o/3"]]],
    ]);
    expect(
      await createDrive({ transport: fake }).prune().orThrow(),
    ).toHaveLength(3);
    const failing = createDrive({
      transport: fake,
      storage: storage("remove"),
    });
    expect((await failing.prune()).ok).toBe(false);
    const none = createDrive({
      transport: transport({ drive_prune: () => [] }),
      storage: files,
    });
    expect(await none.prune().orThrow()).toEqual([]);
  });

  it("sends null for every option left out", async () => {
    const fake = transport({
      drive_create_folder: () => FOLDER,
      drive_list: () => [],
      drive_move: () => FOLDER,
      drive_share: () => GRANT,
      drive_restore: () => ({
        id: "t1",
        batchId: "b1",
        count: 1,
        node: FOLDER,
      }),
      drive_bin: () => [],
      drive_marked: () => [],
    });
    const events: string[] = [];
    const drive = createDrive({
      transport: fake,
      logger: {
        debug: () => undefined,
        info: () => undefined,
        warn: () => undefined,
        error: () => undefined,
      },
      hooks: {
        createFolder: {
          after: () => {
            events.push("created");
          },
        },
      },
    });
    await drive.createFolder("o", { name: "Root" }).orThrow();
    await drive.list("o").orThrow();
    await drive.move("f1", null).orThrow();
    await drive.share("f1", { type: "user", id: "u1" }, "viewer").orThrow();
    await drive.restore("t1").orThrow();
    await drive.bin("o").orThrow();
    await drive.recent("o").orThrow();
    expect(events).toEqual(["created"]);
    expect(fake.calls.map(([, fn, args]) => [fn, args])).toEqual([
      [
        "drive_create_folder",
        {
          tenant: "o",
          parent: null,
          name: "Root",
          conflict: null,
          fields: null,
        },
      ],
      [
        "drive_list",
        { tenant: "o", parent: null, page_size: null, skip: null },
      ],
      ["drive_move", { node: "f1", parent: null, rank: null, conflict: null }],
      [
        "drive_share",
        {
          node: "f1",
          principal_type: "user",
          principal_id: "u1",
          role: "viewer",
          expires_at: null,
        },
      ],
      ["drive_restore", { item: "t1", conflict: null }],
      ["drive_bin", { tenant: "o", page_size: null, before: null }],
      ["drive_marked", { tenant: "o", recent: true, page_size: null }],
    ]);
  });

  it("rejects a node of an unknown kind", async () => {
    const drive = createDrive({
      transport: transport({ drive_get: () => ({ ...FILE, kind: "link" }) }),
    });
    expect((await drive.get("n1")).ok).toBe(false);
  });

  it("describes the managed table as a subject", () => {
    expect(driveSubject()).toMatchObject({
      table: "better_supabase.drive_nodes",
      tenant: "tenant_id",
      permissions: { read: "drive.read", write: "drive.manage" },
      search: { title: "name" },
    });
    expect(driveSubject({ schema: "app" }).table).toBe("app.drive_nodes");
  });
});
