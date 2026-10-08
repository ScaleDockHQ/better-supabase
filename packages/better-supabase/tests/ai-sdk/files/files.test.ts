import { describe, expect, it, vi } from "vitest";

const sdkDownload = vi.hoisted(() =>
  vi.fn(() =>
    Promise.resolve({ data: new Uint8Array([5]), mediaType: "text/plain" }),
  ),
);

vi.mock(import("ai"), async (importOriginal) => ({
  ...(await importOriginal()),
  createDownload: () => sdkDownload,
}));

import type { AiFileStorage } from "../../../src/blocks/ai-files/index.ts";

import {
  aiFileDownload,
  AiFileDownloadError,
  providerFile,
  saveGeneratedFiles,
} from "../../../src/ai-sdk/files/index.ts";
import {
  aiFileUrl,
  createAiFiles,
} from "../../../src/blocks/ai-files/index.ts";

const AT = "2026-01-01T00:00:00Z";

const row = (overrides: Record<string, unknown> = {}) => ({
  id: "f1",
  organization_id: "o1",
  owner_id: "u1",
  chat_id: null,
  project_id: null,
  bucket: "ai-files",
  path: "o1/u1/f1/a.png",
  media_type: "image/png",
  filename: "a.png",
  byte_size: 3,
  sha256: null,
  status: "ready",
  source: "upload",
  created_at: AT,
  uploaded_at: AT,
  expires_at: null,
  ...overrides,
});

function filesWith(
  respond: (fn: string, args: Record<string, unknown>) => unknown,
) {
  const uploads: string[] = [];
  const storage: AiFileStorage = {
    from: () => ({
      createSignedUploadUrl: () =>
        Promise.resolve({ data: { signedUrl: "", token: "" }, error: null }),
      createSignedUrl: () =>
        Promise.resolve({ data: { signedUrl: "" }, error: null }),
      download: () =>
        Promise.resolve({
          data: new Blob([new Uint8Array([7, 8, 9])]),
          error: null,
        }),
      remove: () => Promise.resolve({ data: [], error: null }),
      upload: (path) => {
        uploads.push(path);
        return Promise.resolve({ data: {}, error: null });
      },
    }),
  };
  const call = vi.fn((_schema: string, fn: string, args: object) =>
    Promise.resolve(respond(fn, args as Record<string, unknown>)),
  );
  return {
    files: createAiFiles({ transport: { call }, storage }),
    uploads,
    call,
  };
}

describe("aiFileDownload", () => {
  it("reads storage URLs as the caller and leaves supported URLs to the model", async () => {
    const { files } = filesWith(() => row());
    const fallback = vi.fn(() =>
      Promise.resolve([{ data: new Uint8Array([1]), mediaType: "text/plain" }]),
    );
    const download = aiFileDownload(files, { fallback });
    const result = await download([
      { url: new URL(aiFileUrl(row())), isUrlSupportedByModel: false },
      { url: new URL("https://cdn/x.png"), isUrlSupportedByModel: true },
      { url: new URL("https://cdn/y.txt"), isUrlSupportedByModel: false },
    ]);
    expect(result[0]).toEqual({
      data: new Uint8Array([7, 8, 9]),
      mediaType: "image/png",
    });
    expect(result[1]).toBeNull();
    expect(result[2]?.mediaType).toBe("text/plain");
    expect(fallback).toHaveBeenCalledTimes(1);
  });

  it("throws for a file the caller can't read", async () => {
    const { files } = filesWith(() => null);
    const download = aiFileDownload(files);
    await expect(
      download([
        {
          url: new URL("supabase-storage://ai-files/o2/u2/f2/x.png"),
          isUrlSupportedByModel: false,
        },
      ]),
    ).rejects.toBeInstanceOf(AiFileDownloadError);
  });

  it("downloads other URLs with the AI SDK by default", async () => {
    const { files } = filesWith(() => null);
    const signal = new AbortController().signal;
    const download = aiFileDownload(files, { abortSignal: signal });
    const [result] = await download([
      { url: new URL("https://cdn/y.txt"), isUrlSupportedByModel: false },
    ]);
    expect(result?.data).toEqual(new Uint8Array([5]));
    expect(sdkDownload).toHaveBeenCalledWith({
      url: new URL("https://cdn/y.txt"),
      abortSignal: signal,
    });
  });

  it("refuses other URLs without a fallback", async () => {
    const { files } = filesWith(() => null);
    const download = aiFileDownload(files, { fallback: false });
    await expect(
      download([
        { url: new URL("https://cdn/y"), isUrlSupportedByModel: false },
      ]),
    ).rejects.toThrow(/supabase-storage/);
  });
});

describe("saveGeneratedFiles", () => {
  it("stores each file and returns parts that point at it", async () => {
    const { files, uploads, call } = filesWith((_fn, args) =>
      row({
        source: "generated",
        filename: args["filename"],
        path: `o1/u1/f1/${String(args["filename"])}`,
      }),
    );
    const parts = await saveGeneratedFiles(
      files,
      [{ uint8Array: new Uint8Array([1, 2]), mediaType: "image/png" }],
      { organizationId: "o1", ownerId: "u1", chatId: "c1" },
    );
    expect(parts.ok && parts.data).toEqual([
      {
        type: "file",
        mediaType: "image/png",
        url: "supabase-storage://ai-files/o1/u1/f1/generated-1.png",
        filename: "generated-1.png",
      },
    ]);
    expect(uploads).toEqual(["o1/u1/f1/generated-1.png"]);
    expect(call.mock.calls[0]?.[2]).toMatchObject({ chat_id: "c1" });
  });
});

describe("providerFile", () => {
  it("reuses a cached reference", async () => {
    const { files } = filesWith(() => ({
      file_id: "f1",
      provider: "openai",
      reference: "file-1",
      expires_at: null,
    }));
    const upload = vi.fn();
    const reference = await providerFile(files, "f1", "openai", upload);
    expect(reference.ok && reference.data).toBe("file-1");
    expect(upload).not.toHaveBeenCalled();
  });

  it("uploads once and saves the reference", async () => {
    const { files, call } = filesWith((fn) =>
      fn === "get_ai_provider_file"
        ? null
        : fn === "get_ai_file"
          ? row()
          : true,
    );
    const reference = await providerFile(files, "f1", "openai", (file) => {
      expect([...file.data]).toEqual([7, 8, 9]);
      return Promise.resolve({ reference: "file-2" });
    });
    expect(reference.ok && reference.data).toBe("file-2");
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "set_ai_provider_file",
      expect.objectContaining({ reference: "file-2" }),
    );
  });

  it("turns a failed upload into a network error", async () => {
    const { files } = filesWith((fn) =>
      fn === "get_ai_provider_file" ? null : row(),
    );
    const reference = await providerFile(files, "f1", "openai", () =>
      Promise.reject(new Error("quota")),
    );
    expect(reference.ok ? undefined : reference.error.message).toBe(
      "The openai upload failed: quota",
    );
  });
});
