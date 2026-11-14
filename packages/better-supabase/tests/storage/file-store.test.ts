import type { SupabaseClient } from "@supabase/supabase-js";

import { afterEach, describe, expect, expectTypeOf, it, vi } from "vitest";

import type {
  FileStore,
  SupabaseFileStorage,
} from "../../src/storage/index.ts";

import {
  fileStoreOf,
  supabaseFileStore,
  vercelBlobStore,
} from "../../src/storage/index.ts";
import {
  BlobAccessError,
  BlobContentTypeNotAllowedError,
  BlobError,
  BlobFileTooLargeError,
  BlobNotFoundError,
  BlobServiceRateLimited,
  fakeBlobModule,
  fakeSupabaseStorage,
} from "../fixtures/file-stores.ts";

afterEach(() => {
  vi.useRealTimers();
});

describe("fileStoreOf", () => {
  it("returns a store for API 1 and refuses another", () => {
    const store = vercelBlobStore(fakeBlobModule().module);

    expect(fileStoreOf(store)).toBe(store);
    expect(() =>
      // SAFETY: simulates a store built for a newer API.
      fileStoreOf({ ...store, apiVersion: 2 as never }),
    ).toThrow(/file store "vercel-blob" targets file store API 2/u);
  });
});

describe("supabaseFileStore", () => {
  it("accepts supabase-js storage", () => {
    expectTypeOf<SupabaseClient["storage"]>().toExtend<SupabaseFileStorage>();
  });

  it("calls the Storage methods the blocks called before", async () => {
    const fake = fakeSupabaseStorage();
    const store = supabaseFileStore(fake.storage);

    expect(store).toMatchObject({ apiVersion: 1, name: "supabase" });
    expect(store.storage).toBe(fake.storage);

    await store
      .put("files", "a.txt", new Blob(["a"]), {
        contentType: "text/plain",
        upsert: false,
      })
      .orThrow();
    expect(await (await store.get("files", "a.txt").orThrow()).text()).toBe(
      "a",
    );
    expect(
      await store.signedUrl("files", "a.txt", { expiresIn: 60 }).orThrow(),
    ).toBe("https://storage.test/sign/files/a.txt?ttl=60");
    await store
      .signedUrl("files", "a.txt", { expiresIn: 60, download: "b.txt" })
      .orThrow();
    expect(
      await store.signedUploadUrl?.("files", "b.txt", { maxSize: 5 }).orThrow(),
    ).toEqual({
      url: "https://storage.test/upload/sign/files/b.txt?token=t",
      method: "PUT",
      headers: {},
      token: "t",
    });
    expect(await store.head?.("files", "a.txt").orThrow()).toEqual({
      size: 1,
      contentType: "text/plain",
    });
    expect(await store.head?.("files", "missing").orThrow()).toBeUndefined();
    await store.delete("files", ["a.txt"]).orThrow();
    await store.delete("files", []).orThrow();

    expect(fake.calls).toEqual([
      [
        "upload",
        "files",
        "a.txt",
        { contentType: "text/plain", upsert: false },
      ],
      ["download", "files", "a.txt"],
      ["createSignedUrl", "files", "a.txt", 60, undefined],
      ["createSignedUrl", "files", "a.txt", 60, { download: "b.txt" }],
      ["createSignedUploadUrl", "files", "b.txt"],
      ["info", "files", "a.txt"],
      ["info", "files", "missing"],
      ["remove", "files", ["a.txt"]],
    ]);
  });

  it("maps Storage errors and a client without a method", async () => {
    const fake = fakeSupabaseStorage();
    const store = supabaseFileStore(fake.storage);

    const missing = await store.get("files", "nope");
    expect(missing.ok ? undefined : missing.error).toMatchObject({
      kind: "not_found",
      table: "storage.objects",
    });

    await store.put("files", "a", new Uint8Array([1])).orThrow();
    const taken = await store.put("files", "a", new Uint8Array([2]));
    expect(taken.ok ? undefined : taken.error.kind).toBe("conflict");

    const bare = supabaseFileStore({ from: () => ({}) });

    for (const result of [
      await bare.put("files", "a", new Blob(["a"])),
      await bare.get("files", "a"),
      await bare.delete("files", ["a"]),
      await bare.signedUrl("files", "a", { expiresIn: 1 }),
      await (bare.head?.("files", "a") ?? Promise.resolve(undefined)),
      await (bare.signedUploadUrl?.("files", "a", {}) ??
        Promise.resolve(undefined)),
    ]) {
      expect(result?.ok ? undefined : result?.error).toMatchObject({
        kind: "invalid_request",
        hint: "STORAGE_CLIENT",
      });
    }
  });
});

describe("vercelBlobStore", () => {
  it("is a private store by default and prefixes pathnames", async () => {
    const fake = fakeBlobModule();

    const store: FileStore = vercelBlobStore(fake.module, {
      prefix: "app/",
      token: "rw",
    });

    expect(store).toMatchObject({ apiVersion: 1, name: "vercel-blob" });

    await store
      .put("files", "a.txt", new TextEncoder().encode("hello"), {
        contentType: "text/plain",
      })
      .orThrow();

    const file = await store.get("files", "a.txt").orThrow();

    expect(await file.text()).toBe("hello");
    expect(file.type).toBe("text/plain");
    expect(fake.calls[0]).toEqual([
      "put",
      "app/files/a.txt",
      {
        access: "private",
        contentType: "text/plain",
        allowOverwrite: false,
        addRandomSuffix: false,
        token: "rw",
      },
    ]);
    expect(fake.calls[1]).toEqual([
      "get",
      "app/files/a.txt",
      { access: "private", token: "rw" },
    ]);
  });

  it("overwrites only with upsert, and answers not_found for a missing file", async () => {
    const fake = fakeBlobModule();
    const store = vercelBlobStore(fake.module, { access: "public" });

    await store.put("files", "a", new Blob(["1"])).orThrow();

    const taken = await store.put("files", "a", new Blob(["2"]));
    expect(taken.ok ? undefined : taken.error.kind).toBe("conflict");

    await store.put("files", "a", new Blob(["3"]), { upsert: true }).orThrow();
    expect(fake.calls.at(-1)).toMatchObject([
      "put",
      "files/a",
      { access: "public", allowOverwrite: true },
    ]);

    const missing = await store.get("files", "nope");
    expect(missing.ok ? undefined : missing.error).toMatchObject({
      kind: "not_found",
      code: "NoSuchKey",
    });
    expect(await store.head?.("files", "nope").orThrow()).toBeUndefined();
    expect(await store.head?.("files", "a").orThrow()).toEqual({
      size: 1,
      contentType: "application/octet-stream",
    });
  });

  it("deletes the pathnames in one call, and makes none for an empty list", async () => {
    const fake = fakeBlobModule();
    const store = vercelBlobStore(fake.module, { prefix: "p/" });

    await store.delete("files", []).orThrow();
    expect(fake.calls).toEqual([]);

    await store.delete("files", ["a", "b"]).orThrow();
    expect(fake.calls).toEqual([["del", ["p/files/a", "p/files/b"], {}]]);
  });

  it("signs a download URL for one pathname until expiresIn", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-11-13T12:00:00Z"));
    const fake = fakeBlobModule();
    const store = vercelBlobStore(fake.module, { token: "rw" });
    const until = Date.parse("2026-11-13T12:05:00Z");

    const url = await store
      .signedUrl("files", "a.pdf", { expiresIn: 300 })
      .orThrow();

    expect(url).toBe(
      "https://store.private.blob.vercel-storage.com/files/a.pdf?vercel-blob-operation=get",
    );
    expect(fake.calls).toEqual([
      [
        "issueSignedToken",
        {
          pathname: "files/a.pdf",
          operations: ["get"],
          validUntil: until,
          token: "rw",
        },
      ],
      [
        "presignUrl",
        {
          clientSigningToken: "signing",
          delegationToken: "delegation:files/a.pdf",
          validUntil: until,
        },
        {
          operation: "get",
          pathname: "files/a.pdf",
          validUntil: until,
          access: "private",
        },
      ],
    ]);

    const download = await store
      .signedUrl("files", "a.pdf", { expiresIn: 300, download: "Plan.pdf" })
      .orThrow();

    expect(new URL(download).searchParams.get("download")).toBe("1");

    const without = await vercelBlobStore(
      fakeBlobModule({ downloadUrl: false }).module,
    )
      .signedUrl("files", "a.pdf", { expiresIn: 300, download: true })
      .orThrow();

    expect(new URL(without).searchParams.has("download")).toBe(false);
  });

  it("presigns a put limited to the type and size, without overwrites", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-11-13T12:00:00Z"));
    const fake = fakeBlobModule();
    const store = vercelBlobStore(fake.module);
    const now = Date.parse("2026-11-13T12:00:00Z");

    const upload = await store
      .signedUploadUrl?.("files", "a.pdf", {
        contentType: "application/pdf",
        maxSize: 2048,
      })
      .orThrow();

    expect(upload).toEqual({
      url: "https://store.private.blob.vercel-storage.com/files/a.pdf?vercel-blob-operation=put",
      method: "PUT",
      headers: {
        "x-vercel-blob-access": "private",
        "x-content-type": "application/pdf",
      },
    });
    expect(fake.calls).toEqual([
      [
        "issueSignedToken",
        {
          pathname: "files/a.pdf",
          operations: ["put"],
          validUntil: now + 7_200_000,
          allowedContentTypes: ["application/pdf"],
          maximumSizeInBytes: 2048,
        },
      ],
      [
        "presignUrl",
        expect.anything(),
        {
          operation: "put",
          pathname: "files/a.pdf",
          validUntil: now + 7_200_000,
          access: "private",
          allowOverwrite: false,
          addRandomSuffix: false,
          allowedContentTypes: ["application/pdf"],
          maximumSizeInBytes: 2048,
        },
      ],
    ]);

    fake.calls.length = 0;
    await store.signedUploadUrl?.("files", "b", { expiresIn: 60 }).orThrow();
    expect(fake.calls[0]).toEqual([
      "issueSignedToken",
      { pathname: "files/b", operations: ["put"], validUntil: now + 60_000 },
    ]);
  });

  it("maps the SDK's errors by class name and never throws", async () => {
    const cases = [
      [new BlobNotFoundError(), "not_found"],
      [new BlobAccessError(), "forbidden"],
      [new BlobServiceRateLimited(30), "rate_limited"],
      [new BlobFileTooLargeError(), "invalid_input"],
      [new BlobContentTypeNotAllowedError(), "invalid_input"],
      [new BlobError("Unknown error"), "network"],
      [new TypeError("fetch failed"), "network"],
    ] as const;

    for (const [error, kind] of cases) {
      const store = vercelBlobStore(
        fakeBlobModule({
          fail: { put: error, get: error, del: error, issueSignedToken: error },
        }).module,
      );

      for (const result of [
        await store.put("files", "a", new Blob(["a"])),
        await store.get("files", "a"),
        await store.delete("files", ["a"]),
        await store.signedUrl("files", "a", { expiresIn: 1 }),
        await (store.signedUploadUrl?.("files", "a", {}) ??
          Promise.resolve(undefined)),
      ]) {
        expect(result?.ok ? undefined : result?.error.kind).toBe(kind);
      }
    }

    const limited = await vercelBlobStore(
      fakeBlobModule({ fail: { get: new BlobServiceRateLimited(30) } }).module,
    ).get("files", "a");

    expect(limited.ok ? undefined : limited.error).toMatchObject({
      kind: "rate_limited",
      retryAfter: 30,
      code: "BlobServiceRateLimited",
    });

    const denied = await vercelBlobStore(
      fakeBlobModule({ fail: { head: new BlobAccessError() } }).module,
    ).head?.("files", "a");

    expect(denied?.ok ? undefined : denied?.error.kind).toBe("forbidden");
  });
});
