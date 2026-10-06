import type { SupabaseClient } from "@supabase/supabase-js";

import { describe, expect, expectTypeOf, it } from "vitest";

import type {
  AttachmentStorage,
  ScanVerdict,
} from "../../../src/blocks/attachments/index.ts";

import {
  createAttachments,
  createAttachmentScanner,
} from "../../../src/blocks/attachments/index.ts";

const row = (overrides: Record<string, unknown> = {}) => ({
  id: "a1",
  organization_id: "org-1",
  subject_type: "project",
  subject_id: "p1",
  bucket: "attachments",
  object_path: "org-1/attachments/a1",
  name: "plan.pdf",
  mime_type: "application/pdf",
  size: "2048",
  status: "clean",
  scan_detail: null,
  uploaded_by: "u1",
  created_at: "2026-10-06T12:00:00Z",
  uploaded_at: "2026-10-06T12:00:05Z",
  scanned_at: null,
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
        const result = results[fn];
        return result instanceof Error
          ? Promise.reject(result)
          : Promise.resolve(result);
      },
    },
  };
}

interface Reply {
  data: unknown;
  error: unknown;
}

function fakeStorage(replies: Partial<Record<string, Reply | Error>> = {}) {
  const calls: unknown[][] = [];
  const reply = (method: string, fallback: unknown, ...args: unknown[]) => {
    calls.push([method, ...args]);
    const value = replies[method];
    if (value instanceof Error) return Promise.reject(value);
    return Promise.resolve(value ?? { data: fallback, error: null });
  };
  const storage = {
    from: (bucket: string) => ({
      createSignedUploadUrl: (path: string) =>
        reply(
          "createSignedUploadUrl",
          { signedUrl: `https://s/upload/${path}`, token: "tok" },
          bucket,
          path,
        ),
      createSignedUrl: (path: string, ttl: number, options?: unknown) =>
        reply(
          "createSignedUrl",
          { signedUrl: `https://s/sign/${path}` },
          path,
          ttl,
          options,
        ),
      download: (path: string) => reply("download", new Blob(["hello"]), path),
      remove: (paths: string[]) => reply("remove", [], paths),
    }),
    // SAFETY: each reply has the shape the structural type names.
  } as AttachmentStorage;
  return { calls, storage };
}

describe("createAttachments", () => {
  it("accepts supabase-js storage", () => {
    expectTypeOf<SupabaseClient["storage"]>().toExtend<AttachmentStorage>();
  });

  it("creates the record, then a signed upload URL for its path", async () => {
    const { transport, calls } = fakeTransport({
      create_attachment: row({ status: "pending", uploaded_at: null }),
    });
    const storage = fakeStorage();
    const attachments = createAttachments({
      transport,
      storage: storage.storage,
    });
    const upload = await attachments
      .upload({
        organizationId: "org-1",
        name: "plan.pdf",
        mimeType: "application/pdf",
        size: 2048,
      })
      .orThrow();
    expect(calls[0]).toEqual([
      "create_attachment",
      {
        tenant: "org-1",
        name: "plan.pdf",
        mime_type: "application/pdf",
        size: 2048,
        subject_type: undefined,
        subject_id: undefined,
      },
    ]);
    expect(storage.calls[0]).toEqual([
      "createSignedUploadUrl",
      "attachments",
      "org-1/attachments/a1",
    ]);
    expect(upload).toMatchObject({
      signedUrl: "https://s/upload/org-1/attachments/a1",
      token: "tok",
      attachment: {
        status: "pending",
        size: 2048,
        subjectType: "project",
        uploadedAt: undefined,
      },
    });
    expect(upload.attachment.createdAt.toString()).toBe("2026-10-06T12:00:00Z");
  });

  it("maps storage errors and empty replies", async () => {
    const { transport } = fakeTransport({ create_attachment: row() });
    const denied = createAttachments({
      transport,
      storage: fakeStorage({
        createSignedUploadUrl: {
          data: null,
          error: {
            message: "new row violates row-level security policy",
            statusCode: "403",
          },
        },
      }).storage,
    });
    const upload = await denied.upload({
      organizationId: "org-1",
      name: "x",
      mimeType: "text/plain",
      size: 1,
    });
    expect(upload.ok ? undefined : upload.error.kind).toBe("forbidden");

    const empty = createAttachments({
      transport,
      storage: fakeStorage({
        createSignedUploadUrl: { data: null, error: null },
      }).storage,
    });
    const none = await empty.upload({
      organizationId: "org-1",
      name: "x",
      mimeType: "text/plain",
      size: 1,
    });
    expect(none.ok ? undefined : none.error.message).toBe(
      "Storage returned no data",
    );

    const thrown = createAttachments({
      transport,
      storage: fakeStorage({ createSignedUploadUrl: new Error("offline") })
        .storage,
    });
    const failed = await thrown.upload({
      organizationId: "org-1",
      name: "x",
      mimeType: "text/plain",
      size: 1,
    });
    expect(failed.ok).toBe(false);
  });

  it("signs downloads only for scanned files", async () => {
    const storage = fakeStorage();
    const clean = createAttachments({
      transport: fakeTransport({ get_attachment: row() }).transport,
      storage: storage.storage,
      downloadTtl: 60,
    });
    expect(
      (await clean.download("a1", { as: "plan.pdf" }).orThrow()).signedUrl,
    ).toBe("https://s/sign/org-1/attachments/a1");
    expect(storage.calls[0]).toEqual([
      "createSignedUrl",
      "org-1/attachments/a1",
      60,
      { download: "plan.pdf" },
    ]);
    await clean.download("a1").orThrow();
    expect(storage.calls[1]).toEqual([
      "createSignedUrl",
      "org-1/attachments/a1",
      60,
      undefined,
    ]);

    for (const [status, message] of [
      ["pending", "The file is not scanned yet"],
      ["infected", "The file failed the malware scan"],
    ]) {
      const blocked = await createAttachments({
        transport: fakeTransport({ get_attachment: row({ status }) }).transport,
        storage: storage.storage,
      }).download("a1");
      expect(blocked.ok ? undefined : blocked.error).toMatchObject({
        kind: "invalid_request",
        message,
        hint: "ATTACHMENT_NOT_SCANNED",
      });
    }

    const unscanned = createAttachments({
      transport: fakeTransport({ get_attachment: row({ status: "pending" }) })
        .transport,
      storage: storage.storage,
      requireScan: false,
    });
    expect((await unscanned.download("a1")).ok).toBe(true);
    const notUploaded = await createAttachments({
      transport: fakeTransport({
        get_attachment: row({ status: "pending", uploaded_at: null }),
      }).transport,
      storage: storage.storage,
      requireScan: false,
    }).download("a1");
    expect(notUploaded.ok).toBe(false);
  });

  it("returns not_found for a record the caller can't see", async () => {
    const attachments = createAttachments({
      transport: fakeTransport({ get_attachment: null }).transport,
      storage: fakeStorage().storage,
    });
    const missing = await attachments.get("a1");
    expect(missing.ok ? undefined : missing.error).toMatchObject({
      kind: "not_found",
      hint: "ATTACHMENT_NOT_FOUND",
    });
  });

  it("removes the file before the record, and lists and confirms", async () => {
    const { transport, calls } = fakeTransport({
      get_attachment: row(),
      delete_attachment: true,
      list_attachments: [row(), row({ id: "a2", status: "failed" })],
      confirm_attachment: row(),
    });
    const storage = fakeStorage();
    const attachments = createAttachments({
      transport,
      storage: storage.storage,
    });
    expect(await attachments.remove("a1").orThrow()).toBe(true);
    expect(storage.calls).toEqual([["remove", ["org-1/attachments/a1"]]]);
    expect(calls.map(([fn]) => fn)).toEqual([
      "get_attachment",
      "delete_attachment",
    ]);
    const listed = await attachments
      .list("org-1", { type: "project", id: "p1" })
      .orThrow();
    expect(listed.map((attachment) => attachment.status)).toEqual([
      "clean",
      "failed",
    ]);
    expect(calls.at(-1)).toEqual([
      "list_attachments",
      { tenant: "org-1", subject_type: "project", subject_id: "p1" },
    ]);
    expect((await attachments.confirm("a1").orThrow()).id).toBe("a1");

    const odd = createAttachments({
      transport: fakeTransport({ get_attachment: row({ status: "lost" }) })
        .transport,
      storage: storage.storage,
    });
    await expect(odd.get("a1").orThrow()).rejects.toThrow(
      /Unknown attachment status/,
    );
  });
});

describe("createAttachmentScanner", () => {
  const scanner = (
    results: Record<string, unknown>,
    scan: () => ScanVerdict | Promise<ScanVerdict>,
  ) => {
    const transport = fakeTransport(results);
    const storage = fakeStorage();
    return {
      ...transport,
      storage,
      scanner: createAttachmentScanner({
        transport: transport.transport,
        storage: storage.storage,
        scan,
      }),
    };
  };

  it("downloads a pending file, scans it and records the verdict", async () => {
    const {
      scanner: s,
      calls,
      storage,
    } = scanner(
      {
        get_attachment: row({ status: "pending" }),
        set_attachment_status: row({
          status: "infected",
          scan_detail: "eicar",
        }),
      },
      () => ({ status: "infected", detail: "eicar" }),
    );
    const result = await s.scan("a1").orThrow();
    expect(result).toMatchObject({ status: "infected", scanDetail: "eicar" });
    expect(storage.calls).toEqual([["download", "org-1/attachments/a1"]]);
    expect(calls.at(-1)).toEqual([
      "set_attachment_status",
      { id: "a1", status: "infected", detail: "eicar" },
    ]);
  });

  it("skips settled files and refuses files not uploaded yet", async () => {
    const settled = scanner({ get_attachment: row() }, () => {
      throw new Error("not called");
    });
    expect((await settled.scanner.scan("a1").orThrow()).status).toBe("clean");
    expect(settled.storage.calls).toEqual([]);

    const early = scanner(
      { get_attachment: row({ status: "pending", uploaded_at: null }) },
      () => ({ status: "clean" }),
    );
    const result = await early.scanner.scan("a1");
    expect(result.ok ? undefined : result.error.hint).toBe(
      "ATTACHMENT_NOT_UPLOADED",
    );
  });

  it("records failed when the scan throws, and the job rethrows", async () => {
    const { scanner: s, calls } = scanner(
      {
        get_attachment: row({ status: "failed" }),
        set_attachment_status: row({ status: "failed" }),
      },
      () => Promise.reject(new Error("clamd down")),
    );
    const result = await s.scan("a1");
    expect(result.ok ? undefined : result.error).toMatchObject({
      kind: "raised",
      hint: "ATTACHMENT_SCAN_FAILED",
    });
    expect(calls.at(-1)).toEqual([
      "set_attachment_status",
      { id: "a1", status: "failed", detail: "clamd down" },
    ]);
    await expect(
      s.job(
        { attachmentId: "a1" },
        undefined as never,
        new AbortController().signal,
      ),
    ).rejects.toThrow(/clamd down/);

    const lost = scanner(
      {
        get_attachment: row({ status: "pending" }),
        set_attachment_status: null,
      },
      () => Promise.reject(new Error("x")),
    );
    const missing = await lost.scanner.scan("a1");
    expect(missing.ok ? undefined : missing.error.hint).toBe(
      "ATTACHMENT_NOT_FOUND",
    );
  });

  it("scans the files of attachment.uploaded events only", async () => {
    const { scanner: s, calls } = scanner(
      {
        get_attachment: row({ status: "pending" }),
        set_attachment_status: row(),
      },
      () => ({ status: "clean" }),
    );
    await s.sink().send([
      {
        specversion: "1.0",
        id: "1",
        source: "/t",
        type: "dev.better-supabase.attachment.uploaded",
        data: { attachmentId: "a1" },
      },
      {
        specversion: "1.0",
        id: "2",
        source: "/t",
        type: "attachment.uploaded",
        data: {},
      },
      {
        specversion: "1.0",
        id: "3",
        source: "/t",
        type: "dev.better-supabase.attachment.scanned",
        data: { attachmentId: "a1" },
      },
      {
        specversion: "1.0",
        id: "4",
        source: "/t",
        type: "attachment.uploaded",
      },
    ]);
    expect(calls.map(([fn]) => fn)).toEqual([
      "get_attachment",
      "set_attachment_status",
    ]);
  });
});
