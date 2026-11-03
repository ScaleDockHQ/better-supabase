import type { UIMessage } from "ai";

import { describe, expect, it, vi } from "vitest";

import type { AiFiles } from "../../../src/blocks/ai-files/index.ts";

import {
  providerFileParts,
  uploadToProvider,
} from "../../../src/ai-sdk/files/index.ts";
import { aiFileUrl } from "../../../src/blocks/ai-files/index.ts";
import { AsyncResult } from "../../../src/core/result.ts";

const FILE = {
  id: "f1",
  bucket: "ai-files",
  path: "o1/u1/f1/a.png",
  mediaType: "image/png",
  filename: "a.png",
};

function fakeFiles(initial: Record<string, string> = {}) {
  const refs = new Map(Object.entries(initial));
  const upserts: unknown[] = [];

  const files = {
    files: {
      resolve: vi.fn(() => AsyncResult.ok(FILE)),
      read: vi.fn(() =>
        AsyncResult.ok({ file: FILE, data: new Uint8Array([1, 2, 3]) }),
      ),
    },
    providerFiles: {
      get: vi.fn(({ provider }: { provider: string }) => {
        const reference = refs.get(provider);

        return AsyncResult.ok(
          reference === undefined
            ? undefined
            : { fileId: "f1", provider, reference, expiresAt: undefined },
        );
      }),
      upsert: vi.fn((input: { provider: string; reference: string }) => {
        refs.set(input.provider, input.reference);
        upserts.push(input);

        return AsyncResult.ok(true);
      }),
    },
  };

  // SAFETY: the functions under test use only these members.
  return { files: files as unknown as AiFiles, mocks: files, upserts };
}

function fakeApi(expiresAt?: Date) {
  const uploadFile = vi.fn(async () => ({
    providerReference: { openai: "file-9" },
    ...(expiresAt === undefined ? {} : { expiresAt }),
    warnings: [],
  }));

  return {
    uploadFile,
    api: {
      specificationVersion: "v4" as const,
      provider: "openai",
      uploadFile,
    },
  };
}

describe("uploadToProvider", () => {
  it("uploads the stored bytes and records each provider reference", async () => {
    const { files, upserts } = fakeFiles();
    const { api, uploadFile } = fakeApi(new Date("2026-02-01T00:00:00Z"));
    const result = await uploadToProvider(files, "f1", { api });

    expect(result.ok && result.data.providerReference).toEqual({
      openai: "file-9",
    });
    expect(uploadFile).toHaveBeenCalledOnce();
    expect(upserts).toHaveLength(1);
    expect(upserts[0]).toMatchObject({
      fileId: "f1",
      provider: "openai",
      reference: "file-9",
    });
    expect(result.ok && result.data.expiresAt?.toString()).toBe(
      "2026-02-01T00:00:00Z",
    );
  });

  it("returns a typed error when the provider fails", async () => {
    const { files } = fakeFiles();

    const api = {
      specificationVersion: "v4" as const,
      provider: "openai",
      uploadFile: async () => {
        throw new Error("quota");
      },
    };

    const result = await uploadToProvider(files, "f1", { api });
    expect(!result.ok && result.error.hint).toBe("AI_PROVIDER_FILE_UPLOAD");
  });
});

describe("providerFileParts", () => {
  const message = (url: string): UIMessage => ({
    id: "m1",
    role: "user",
    parts: [
      { type: "text", text: "see" },
      { type: "file", mediaType: "image/png", url },
    ],
  });

  it("uploads missing references once and rewrites storage parts", async () => {
    const { files } = fakeFiles();
    const { api, uploadFile } = fakeApi();
    const url = aiFileUrl(FILE);

    const result = await providerFileParts(
      files,
      [message(url), message(url), message("https://x.test/a.png")],
      { api, provider: "openai" },
    );

    expect(result.ok).toBe(true);
    const out = result.ok ? result.data : [];
    expect(uploadFile).toHaveBeenCalledOnce();
    expect(out[0]?.parts[1]).toMatchObject({
      providerReference: { openai: "file-9" },
      url,
    });
    expect(out[2]?.parts[1]).not.toHaveProperty("providerReference");
  });

  it("reuses a valid stored reference without uploading", async () => {
    const { files } = fakeFiles({ openai: "file-1" });
    const { api, uploadFile } = fakeApi();

    const result = await providerFileParts(files, [message(aiFileUrl(FILE))], {
      api,
      provider: "openai",
    });

    expect(uploadFile).not.toHaveBeenCalled();
    expect(result.ok && result.data[0]?.parts[1]).toMatchObject({
      providerReference: { openai: "file-1" },
    });
  });

  it("fails when the upload returns no entry for the provider", async () => {
    const { files } = fakeFiles();
    const { api } = fakeApi();

    const result = await providerFileParts(files, [message(aiFileUrl(FILE))], {
      api,
      provider: "anthropic",
    });

    expect(result.ok).toBe(false);
  });
});
