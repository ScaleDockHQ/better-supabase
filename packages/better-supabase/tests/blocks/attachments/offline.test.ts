import { describe, expect, it } from "vitest";

import type { AttachmentStorage } from "../../../src/blocks/attachments/index.ts";

import {
  createAttachments,
  createAttachmentSweeper,
} from "../../../src/blocks/attachments/index.ts";

const row = (overrides: Record<string, unknown> = {}) => ({
  id: "a1",
  organization_id: "org-1",
  subject_type: null,
  subject_id: null,
  bucket: "attachments",
  object_path: "org-1/attachments/a1",
  name: "plan.pdf",
  mime_type: "application/pdf",
  size: "2048",
  status: "pending",
  scan_detail: null,
  uploaded_by: "u1",
  created_at: "2026-10-06T12:00:00Z",
  uploaded_at: "2026-10-06T12:00:05Z",
  scanned_at: null,
  version: 2,
  ...overrides,
});

function fakeTransport(results: Record<string, unknown>) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    transport: {
      call(
        _schema: string,
        fn: string,
        args: Readonly<Record<string, unknown>>,
      ) {
        calls.push([fn, { ...args }]);

        return Promise.resolve(results[fn]);
      },
    },
  };
}

function fakeStorage(failing: ReadonlySet<string> = new Set()) {
  const calls: unknown[][] = [];

  const storage = {
    from: (bucket: string) => ({
      remove: (paths: string[]) => {
        calls.push([bucket, paths]);

        return Promise.resolve(
          failing.has(bucket)
            ? { data: null, error: { message: "denied", statusCode: "403" } }
            : { data: [], error: null },
        );
      },
    }),
    // SAFETY: the tests only call remove.
  } as unknown as AttachmentStorage;

  return { calls, storage };
}

describe("attachments with offline", () => {
  it("deletes the record first, then every version's file", async () => {
    const { transport, calls } = fakeTransport({
      get_attachment: row({ object_path: "org-1/attachments/a1-v2" }),
      list_attachment_versions: [
        {
          id: "v1",
          attachment_id: "a1",
          version: 1,
          bucket: "attachments",
          object_path: "org-1/attachments/a1",
          name: "plan.pdf",
          mime_type: "application/pdf",
          size: "1",
          status: "clean",
          uploaded_at: "2026-10-06T12:00:00Z",
          archived_at: "2026-10-06T12:00:00Z",
        },
      ],
      delete_attachment: true,
    });

    const storage = fakeStorage();

    const attachments = createAttachments({
      transport,
      storage: storage.storage,
      tenant: "org-1",
      offline: true,
    });

    expect(await attachments.remove("a1").orThrow()).toBe(true);
    expect(calls.map(([fn]) => fn)).toEqual([
      "get_attachment",
      "list_attachment_versions",
      "delete_attachment",
    ]);
    expect(storage.calls).toEqual([
      ["attachments", ["org-1/attachments/a1-v2", "org-1/attachments/a1"]],
    ]);
  });

  it("succeeds when the file delete fails, leaving it queued", async () => {
    const { transport } = fakeTransport({
      get_attachment: row({ version: 1 }),
      list_attachment_versions: [],
      delete_attachment: true,
    });

    const storage = fakeStorage(new Set(["attachments"]));

    const attachments = createAttachments({
      transport,
      storage: storage.storage,
      tenant: "org-1",
      offline: true,
    });

    expect(await attachments.remove("a1").orThrow()).toBe(true);
  });

  it("reads an uploaded, unscanned file unless requireScan says otherwise", async () => {
    const { transport } = fakeTransport({ get_attachment: row() });
    const storage = { from: () => ({ download: () => ({}) }) };

    const offline = createAttachments({
      transport,
      // SAFETY: the gate fails before storage is read.
      storage: storage as unknown as AttachmentStorage,
      tenant: "org-1",
      offline: true,
      requireScan: true,
    });

    expect(await offline.download({ id: "a1" })).toMatchObject({
      ok: false,
      error: { hint: "ATTACHMENT_NOT_SCANNED" },
    });
  });
});

describe("createAttachmentSweeper", () => {
  it("deletes the queued objects per bucket and completes the ones Storage took", async () => {
    const { transport, calls } = fakeTransport({
      queued_attachment_objects: [
        { bucket: "attachments", path: "o/a/1", attempts: 1 },
        { bucket: "media", path: "o/a/2", attempts: 1 },
        { bucket: "attachments", path: "o/a/3", attempts: 2 },
      ],
      complete_attachment_cleanup: 2,
    });

    const storage = fakeStorage(new Set(["media"]));

    const sweeper = createAttachmentSweeper({
      transport,
      storage: storage.storage,
    });

    expect(await sweeper.sweepQueued({ limit: 3 }).orThrow()).toEqual({
      removed: 2,
      failed: 1,
    });
    expect(storage.calls).toEqual([
      ["attachments", ["o/a/1", "o/a/3"]],
      ["media", ["o/a/2"]],
    ]);
    expect(calls).toEqual([
      ["queued_attachment_objects", { max_items: 3 }],
      [
        "complete_attachment_cleanup",
        {
          objects: [
            { bucket: "attachments", path: "o/a/1" },
            { bucket: "attachments", path: "o/a/3" },
          ],
        },
      ],
    ]);
  });

  it("skips the completion when nothing was removed", async () => {
    const { transport, calls } = fakeTransport({
      queued_attachment_objects: [],
    });

    const sweeper = createAttachmentSweeper({
      transport,
      storage: fakeStorage().storage,
    });

    expect(await sweeper.sweepQueued().orThrow()).toEqual({
      removed: 0,
      failed: 0,
    });
    expect(calls).toEqual([["queued_attachment_objects", { max_items: 100 }]]);
  });
});
