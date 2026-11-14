import { describe, expect, it } from "vitest";

import type { FileStore } from "../../../src/storage/file-store.ts";

import { AsyncResult } from "../../../src/core/result.ts";
import {
  supabaseFileStore,
  vercelBlobStore,
} from "../../../src/storage/file-store.ts";
import { ConformanceError } from "../../../src/testing/conformance.ts";
import { testFileStore } from "../../../src/testing/kits/file-store.ts";
import {
  fakeBlobModule,
  fakeSupabaseStorage,
} from "../../fixtures/file-stores.ts";

async function failures(
  store: FileStore,
  fetch?: (url: string, init?: RequestInit) => Promise<Response>,
): Promise<string[]> {
  const error = await testFileStore(store, {
    bucket: "files",
    ...(fetch === undefined ? {} : { fetch }),
  }).then(
    () => undefined,
    (cause: unknown) => cause,
  );

  expect(error).toBeInstanceOf(ConformanceError);

  return (error as ConformanceError).report.checks
    .filter((check) => !check.ok)
    .map((check) => check.name);
}

describe("testFileStore", () => {
  it("passes vercelBlobStore over an in-memory Blob module, fetching the URLs", async () => {
    const fake = fakeBlobModule();

    const report = await testFileStore(vercelBlobStore(fake.module), {
      bucket: "files",
      path: "kit/one.txt",
      fetch: fake.fetch,
    });

    expect(report.subject).toBe('FileStore "vercel-blob"');
    expect(report.checks.map((check) => check.name)).toContain(
      "signs an upload URL",
    );
    expect(report.checks.every((check) => check.ok)).toBe(true);
    expect(fake.blobs.size).toBe(0);
  });

  it("passes supabaseFileStore over an in-memory Storage", async () => {
    const fake = fakeSupabaseStorage();

    const report = await testFileStore(supabaseFileStore(fake.storage), {
      bucket: "files",
      fetch: fake.fetch,
    });

    expect(report.subject).toBe('FileStore "supabase"');
    expect(report.checks.every((check) => check.ok)).toBe(true);
    expect(fake.objects.size).toBe(0);
  });

  it("skips head and signedUploadUrl on a store without them", async () => {
    const full = vercelBlobStore(fakeBlobModule().module);

    const store: FileStore = {
      apiVersion: 1,
      name: "bare",
      put: (...args) => full.put(...args),
      get: (...args) => full.get(...args),
      delete: (...args) => full.delete(...args),
      signedUrl: (...args) => full.signedUrl(...args),
    };

    const report = await testFileStore(store, { bucket: "files" });

    expect(report.checks.map((check) => check.name)).not.toContain(
      "signs an upload URL",
    );
    expect(report.checks.every((check) => check.ok)).toBe(true);
  });

  it("fails a store that overwrites without upsert and keeps deleted files", async () => {
    const store = vercelBlobStore(fakeBlobModule().module);

    expect(
      await failures({
        ...store,
        put: (bucket, path, body, options) =>
          store.put(bucket, path, body, { ...options, upsert: true }),
        delete: () => AsyncResult.ok(undefined),
      }),
    ).toEqual([
      "refuses a put without upsert on a taken path",
      "deletes files, after which get answers not_found",
    ]);
  });

  it("fails another apiVersion, a missing head that finds files, and a bad URL", async () => {
    const store = vercelBlobStore(fakeBlobModule().module);

    expect(
      await failures({
        ...store,
        // SAFETY: simulates a store built for a newer API.
        apiVersion: 2 as never,
        signedUrl: () => AsyncResult.ok("not a url"),
        head: () => AsyncResult.ok({ size: 1, contentType: "text/plain" }),
      }),
    ).toEqual([
      "has apiVersion 1 and a name",
      "signs a download URL",
      "reads the size and type with head, and undefined for a missing file",
    ]);
  });

  it("fails a signed URL that serves nothing", async () => {
    const fake = fakeBlobModule();

    expect(
      await failures(vercelBlobStore(fake.module), () =>
        Promise.resolve(new Response(null, { status: 403 })),
      ),
    ).toEqual(["signs a download URL", "signs an upload URL"]);
  });
});
