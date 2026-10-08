import { describe, expect, it, vi } from "vitest";

import type {
  AiFileBucket,
  AiFileStorage,
} from "../../../src/blocks/ai-files/index.ts";
import type { BlockTransport } from "../../../src/core/block-transport.ts";

import {
  aiFileUrl,
  createAiFiles,
  parseAiFileUrl,
} from "../../../src/blocks/ai-files/index.ts";

const AT = "2026-01-01T00:00:00Z";

const fileRow = (overrides: Record<string, unknown> = {}) => ({
  id: "f1",
  organization_id: "o1",
  owner_id: "u1",
  chat_id: "c1",
  project_id: null,
  bucket: "ai-files",
  path: "o1/u1/f1/report one.pdf",
  media_type: "application/pdf",
  filename: "report one.pdf",
  byte_size: 4,
  sha256: null,
  status: "ready",
  source: "upload",
  created_at: AT,
  uploaded_at: AT,
  expires_at: null,
  ...overrides,
});

const documentRow = {
  id: "d1",
  organization_id: "o1",
  owner_id: "u1",
  chat_id: "c1",
  kind: "code",
  title: "main.ts",
  current_version: 2,
  created_at: AT,
  updated_at: AT,
};

function fakeBucket(): AiFileBucket & {
  readonly calls: string[];
} {
  const calls: string[] = [];
  return {
    calls,
    createSignedUploadUrl: (path) => {
      calls.push(`upload-url:${path}`);
      return Promise.resolve({
        data: { signedUrl: `https://up/${path}`, token: "t" },
        error: null,
      });
    },
    createSignedUrl: (path, ttl) => {
      calls.push(`sign:${path}:${String(ttl)}`);
      return Promise.resolve({
        data: { signedUrl: `https://get/${path}` },
        error: null,
      });
    },
    download: (path) => {
      calls.push(`download:${path}`);
      return Promise.resolve({
        data: new Blob([new Uint8Array([1, 2, 3, 4])]),
        error: null,
      });
    },
    remove: (paths) => {
      calls.push(`remove:${paths.join(",")}`);
      return Promise.resolve({ data: [], error: null });
    },
    upload: (path) => {
      calls.push(`put:${path}`);
      return Promise.resolve({ data: { path }, error: null });
    },
  };
}

function setup(
  respond: (fn: string, args: Record<string, unknown>) => unknown,
  maxBytes?: number,
) {
  const bucket = fakeBucket();
  const storage: AiFileStorage = { from: () => bucket };
  const user = vi.fn((_schema: string, fn: string, args: object) =>
    Promise.resolve(respond(fn, args as Record<string, unknown>)),
  );
  const server = vi.fn((_schema: string, fn: string, args: object) =>
    Promise.resolve(respond(fn, args as Record<string, unknown>)),
  );
  const transport: BlockTransport = { call: user };
  const service: BlockTransport = { call: server };
  const files = createAiFiles({
    transport,
    service,
    storage,
    downloadTtl: 60,
    ...(maxBytes === undefined ? {} : { maxBytes }),
  });
  return { files, bucket, user, server };
}

describe("supabase-storage URLs", () => {
  it("round-trips a path with spaces", () => {
    const url = aiFileUrl({
      bucket: "ai-files",
      path: "o1/u1/f1/report one.pdf",
    });
    expect(url).toBe("supabase-storage://ai-files/o1/u1/f1/report%20one.pdf");
    expect(parseAiFileUrl(url)).toEqual({
      bucket: "ai-files",
      path: "o1/u1/f1/report one.pdf",
    });
  });

  it("rejects other schemes and empty paths", () => {
    expect(parseAiFileUrl("https://example.com/a")).toBeUndefined();
    expect(parseAiFileUrl("supabase-storage://ai-files")).toBeUndefined();
    expect(parseAiFileUrl("not a url")).toBeUndefined();
  });
});

describe("createAiFiles", () => {
  it("reserves a file, then returns a signed upload URL for its path", async () => {
    const { files, bucket, user } = setup(() => fileRow({ status: "pending" }));
    const upload = await files.files.upload("o1", {
      filename: "report one.pdf",
      mediaType: "application/pdf",
      size: 4,
      chatId: "c1",
    });
    expect(upload.ok && upload.data.signedUrl).toBe(
      "https://up/o1/u1/f1/report one.pdf",
    );
    expect(user).toHaveBeenCalledWith("better_supabase", "reserve_ai_file", {
      tenant: "o1",
      filename: "report one.pdf",
      media_type: "application/pdf",
      byte_size: 4,
      chat_id: "c1",
      project_id: undefined,
    });
    expect(bucket.calls).toEqual(["upload-url:o1/u1/f1/report one.pdf"]);
  });

  it("resolves a URL through the caller's access and reads its bytes", async () => {
    const { files, user } = setup((fn) =>
      fn === "get_ai_file_by_path" ? fileRow() : null,
    );
    const resolved = await files.files.resolve(aiFileUrl(fileRow()));
    expect(resolved.ok && resolved.data.id).toBe("f1");
    expect(user).toHaveBeenCalledWith(
      "better_supabase",
      "get_ai_file_by_path",
      { bucket: "ai-files", path: "o1/u1/f1/report one.pdf" },
    );
    const read = await files.files.read(resolved.ok ? resolved.data : "f1");
    expect(read.ok && [...read.data.data]).toEqual([1, 2, 3, 4]);
  });

  it("fails with not_found for a file the caller can't see", async () => {
    const { files } = setup(() => null);
    const result = await files.files.get("f9");
    expect(result.ok ? undefined : result.error.kind).toBe("not_found");
    const bad = await files.files.resolve("https://example.com/x");
    expect(bad.ok ? undefined : bad.error.hint).toBe("AI_FILE_URL");
  });

  it("won't sign or read a pending file, or one over maxBytes", async () => {
    const pending = setup(() => fileRow({ status: "pending" }));
    const signed = await pending.files.files.sign("f1");
    expect(signed.ok ? undefined : signed.error.hint).toBe("AI_FILE_NOT_READY");
    const large = setup(() => fileRow({ byte_size: 10 }), 5);
    const read = await large.files.files.read("f1");
    expect(read.ok ? undefined : read.error.hint).toBe("AI_FILE_TOO_LARGE");
    const lying = setup(() => fileRow({ byte_size: 1 }), 2);
    const big = await lying.files.files.read("f1");
    expect(big.ok ? undefined : big.error.hint).toBe("AI_FILE_TOO_LARGE");
  });

  it("removes the object the delete hands back", async () => {
    const { files, bucket } = setup(() => ({
      bucket: "ai-files",
      path: "o1/u1/f1/a.pdf",
    }));
    const removed = await files.files.remove("f1");
    expect(removed.ok && removed.data).toBe(true);
    expect(bucket.calls).toEqual(["remove:o1/u1/f1/a.pdf"]);
    const none = setup(() => null);
    const nothing = await none.files.files.remove("f1");
    expect(nothing.ok && nothing.data).toBe(false);
  });

  it("stores a generated file as the service role and uploads it", async () => {
    const { files, bucket, server } = setup(() =>
      fileRow({
        source: "generated",
        filename: "a.png",
        path: "o1/u1/f1/a.png",
      }),
    );
    const stored = await files.files.store("o1", {
      ownerId: "u1",
      filename: "a.png",
      mediaType: "image/png",
      data: new Uint8Array([1, 2]),
    });
    expect(stored.ok && stored.data.source).toBe("generated");
    expect(server.mock.calls[0]?.[2]).toMatchObject({
      owner: "u1",
      byte_size: 2,
      source: "generated",
    });
    expect(bucket.calls).toEqual(["put:o1/u1/f1/a.png"]);
  });

  it("deletes the record when the generated file fails to upload", async () => {
    const bucket = fakeBucket();
    const storage: AiFileStorage = {
      from: () => ({
        ...bucket,
        upload: () =>
          Promise.resolve({ data: null, error: { message: "full" } }),
      }),
    };
    const server = vi.fn((_schema: string, fn: string) =>
      Promise.resolve(fn === "store_ai_file" ? fileRow() : true),
    );
    const files = createAiFiles({
      transport: { call: server },
      service: { call: server },
      storage,
    });
    const stored = await files.files.store("o1", {
      ownerId: "u1",
      filename: "a.png",
      mediaType: "image/png",
      data: new Blob([new Uint8Array([1])]),
    });
    expect(stored.ok).toBe(false);
    expect(server.mock.calls.map((call) => call[1])).toEqual([
      "store_ai_file",
      "delete_ai_file",
    ]);
  });

  it("confirms and lists files", async () => {
    const { files, user } = setup((fn) =>
      fn === "list_ai_files" ? [fileRow()] : fileRow(),
    );
    const confirmed = await files.files.confirm("f1", "abc");
    expect(confirmed.ok && confirmed.data.status).toBe("ready");
    expect(user).toHaveBeenLastCalledWith(
      "better_supabase",
      "confirm_ai_file",
      {
        file_id: "f1",
        sha256: "abc",
      },
    );
    const listed = await files.files.list("c1");
    expect(listed.ok && listed.data.map((file) => file.id)).toEqual(["f1"]);
  });

  it("lists provider references that expire soon", async () => {
    const { files } = setup(() => [
      { file_id: "f1", provider: "openai", reference: "r", expires_at: AT },
    ]);
    const expiring = await files.providerFiles.expiring("1 day", 10);
    expect(expiring.ok && expiring.data[0]?.reference).toBe("r");
  });

  it("rolls back, removes and resolves suggestions on documents", async () => {
    const suggestion = {
      id: "s1",
      document_id: "d1",
      version: 2,
      original_text: "a",
      suggested_text: "b",
      description: "shorter",
      created_by: "u1",
      created_at: AT,
      resolved_at: AT,
      accepted: true,
    };
    const { files, user } = setup((fn) => {
      switch (fn) {
        case "delete_ai_document":
          return true;
        case "suggest_ai_document_edit":
        case "resolve_ai_suggestion":
          return suggestion;
        default:
          return documentRow;
      }
    });
    const rolled = await files.documents.rollback("d1", 1);
    expect(rolled.ok && rolled.data.version).toBe(2);
    expect(user).toHaveBeenLastCalledWith(
      "better_supabase",
      "rollback_ai_document",
      { document_id: "d1", version: 1 },
    );
    const removed = await files.documents.remove("d1");
    expect(removed.ok && removed.data).toBe(true);
    const suggested = await files.documents.suggest("d1", {
      originalText: "a",
      suggestedText: "b",
    });
    expect(suggested.ok && suggested.data.suggestedText).toBe("b");
    const resolved = await files.documents.resolve("s1", true);
    expect(resolved.ok && resolved.data.accepted).toBe(true);
  });

  it("purges records, then their objects per bucket", async () => {
    const { files, bucket } = setup(() => [
      { bucket: "ai-files", path: "a" },
      { bucket: "ai-files", path: "b" },
    ]);
    const purged = await files.files.purge({ batch: 10 });
    expect(purged.ok && purged.data).toBe(2);
    expect(bucket.calls).toEqual(["remove:a,b"]);
  });

  it("reads and writes provider file references", async () => {
    const { files, server } = setup((fn) =>
      fn === "get_ai_provider_file"
        ? {
            file_id: "f1",
            provider: "openai",
            reference: "file-abc",
            expires_at: AT,
          }
        : true,
    );
    const cached = await files.providerFiles.get("f1", "openai");
    expect(cached.ok && cached.data?.reference).toBe("file-abc");
    await files.providerFiles.set(
      "f1",
      "openai",
      "file-abc",
      Temporal.Instant.from(AT),
    );
    expect(server).toHaveBeenLastCalledWith(
      "better_supabase",
      "set_ai_provider_file",
      {
        file_id: "f1",
        provider: "openai",
        reference: "file-abc",
        expires_at: "2026-01-01T00:00:00Z",
      },
    );
  });

  it("versions documents and maps their rows", async () => {
    const { files, user } = setup((fn) => {
      switch (fn) {
        case "get_ai_document":
          return { ...documentRow, content: "let a = 1", storage_path: null };
        case "list_ai_document_versions":
          return [
            {
              document_id: "d1",
              version: 2,
              content: "let a = 1",
              storage_path: null,
              created_by_message_id: "m1",
              created_by: "u1",
              created_at: AT,
            },
          ];
        case "list_ai_suggestions":
          return [
            {
              id: "s1",
              document_id: "d1",
              version: 2,
              original_text: "a",
              suggested_text: "b",
              description: null,
              created_by: "u1",
              created_at: AT,
              resolved_at: null,
              accepted: null,
            },
          ];
        default:
          return documentRow;
      }
    });
    const doc = await files.documents.get("d1");
    expect(doc.ok && doc.data.content).toBe("let a = 1");
    expect(doc.ok && doc.data.kind).toBe("code");
    await files.documents.update("d1", { content: "x", expectedVersion: 2 });
    expect(user).toHaveBeenLastCalledWith(
      "better_supabase",
      "update_ai_document",
      expect.objectContaining({ content: "x", expected_version: 2 }),
    );
    const versions = await files.documents.versions("d1");
    expect(versions.ok && versions.data[0]?.messageId).toBe("m1");
    const suggestions = await files.documents.suggestions("d1");
    expect(suggestions.ok && suggestions.data[0]?.accepted).toBeUndefined();
  });

  it("creates a document for an owner through the service role", async () => {
    const { files, user, server } = setup(() => documentRow);
    await files.documents.create("o1", {
      kind: "text",
      title: "Notes",
      ownerId: "u1",
    });
    expect(user).not.toHaveBeenCalled();
    expect(server.mock.calls[0]?.[1]).toBe("create_ai_document");
  });

  it("signs the storage URLs of file parts it may read", async () => {
    const { files } = setup((fn, args) =>
      fn === "get_ai_file_by_path" && args["path"] === "o1/u1/f1/report one.pdf"
        ? fileRow()
        : null,
    );
    const own = aiFileUrl(fileRow());
    const other = "supabase-storage://ai-files/o2/u2/f2/x.pdf";
    const [message] = await files.sign([
      {
        id: "m1",
        role: "user",
        parts: [
          { type: "text", text: "see" },
          { type: "file", mediaType: "application/pdf", url: own },
          { type: "file", mediaType: "application/pdf", url: other },
          { type: "file", mediaType: "image/png", url: "https://cdn/x.png" },
        ],
      },
    ]);
    const urls = message?.parts.map((part) =>
      part.type === "file" ? part.url : part.type,
    );
    expect(urls).toEqual([
      "text",
      "https://get/o1/u1/f1/report one.pdf",
      other,
      "https://cdn/x.png",
    ]);
  });

  it("returns messages untouched without storage URLs", async () => {
    const { files } = setup(() => null);
    const messages = [
      {
        id: "m1",
        role: "user" as const,
        parts: [{ type: "text" as const, text: "hi" }],
      },
    ];
    expect(await files.sign(messages)).toBe(messages);
  });
});
