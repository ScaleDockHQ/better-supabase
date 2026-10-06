import { describe, expect, it, vi } from "vitest";

import {
  defineBucket,
  fromStorageError,
  type StorageClient,
} from "../../src/storage/index.ts";
import {
  lifecyclePayload,
  sameLifecycle,
  toVersion,
} from "../../src/storage/versioning.ts";

const documents = defineBucket({
  id: "documents",
  path: "{organizationId}/{file}",
  versioning: true,
  lifecycle: {
    rules: [{ noncurrentVersionExpiration: { noncurrentDays: 30 } }],
  },
});

function fileApi(overrides: Record<string, unknown> = {}) {
  const api = {
    listV2: vi.fn(async () => ({
      data: { hasNext: false, folders: [], objects: [] },
      error: null,
    })),
    remove: vi.fn(async () => ({ data: [], error: null })),
    purgeCache: vi.fn(async () => ({
      data: { message: "success" },
      error: null,
    })),
    download: vi.fn(async () => ({ data: new Blob(["old"]), error: null })),
    copy: vi.fn(async () => ({ data: { path: "x" }, error: null })),
    move: vi.fn(async () => ({ data: { message: "ok" }, error: null })),
    createSignedUrl: vi.fn(async () => ({
      data: { signedUrl: "https://signed" },
      error: null,
    })),
    createSignedUrls: vi.fn(async (paths: string[]) => ({
      data: paths.map((path) => ({ path, signedUrl: `https://${path}` })),
      error: null,
    })),
    getPublicUrl: vi.fn(() => ({ data: { publicUrl: "https://public" } })),
    ...overrides,
  };
  const client = {
    storage: { from: () => api },
  } as unknown as StorageClient;
  return { api, client };
}

describe("lifecycle", () => {
  it("fills Storage's defaults", () => {
    expect(
      lifecyclePayload("b", {
        rules: [
          {
            id: "history",
            noncurrentVersionExpiration: {
              noncurrentDays: 7,
              newerNoncurrentVersions: 3,
            },
          },
          {
            status: "Disabled",
            noncurrentVersionExpiration: { noncurrentDays: 90 },
          },
        ],
      }),
    ).toEqual({
      rules: [
        {
          id: "history",
          status: "Enabled",
          filter: {},
          noncurrentVersionExpiration: {
            noncurrentDays: 7,
            newerNoncurrentVersions: 3,
          },
        },
        {
          status: "Disabled",
          filter: {},
          noncurrentVersionExpiration: { noncurrentDays: 90 },
        },
      ],
    });
  });

  it("refuses policies Storage would reject", () => {
    const rule = (noncurrentDays: number, newer?: number) => ({
      noncurrentVersionExpiration: {
        noncurrentDays,
        ...(newer === undefined ? {} : { newerNoncurrentVersions: newer }),
      },
    });
    expect(() => lifecyclePayload("b", { rules: [rule(0)] })).toThrow(
      "noncurrentDays must be a whole number of days",
    );
    expect(() => lifecyclePayload("b", { rules: [rule(1.5)] })).toThrow(
      "noncurrentDays",
    );
    expect(() => lifecyclePayload("b", { rules: [rule(1, 101)] })).toThrow(
      "newerNoncurrentVersions must be 1 to 100",
    );
    expect(() =>
      lifecyclePayload("b", {
        rules: [
          { id: "a", ...rule(1) },
          { id: "a", ...rule(2) },
        ],
      }),
    ).toThrow("lifecycle rule ids repeat");
    expect(() =>
      lifecyclePayload("b", { rules: [] as unknown as [never] }),
    ).toThrow("1 to 1000 rules");
  });

  it("needs versioning", () => {
    expect(() =>
      defineBucket({
        id: "plain",
        path: "{file}",
        lifecycle: {
          rules: [{ noncurrentVersionExpiration: { noncurrentDays: 1 } }],
        },
      }),
    ).toThrow("needs versioning: true");
  });

  it("compares stored policies without generated ids", () => {
    const expected = lifecyclePayload("b", {
      rules: [{ noncurrentVersionExpiration: { noncurrentDays: 30 } }],
    });
    expect(
      sameLifecycle(expected, {
        rules: [
          {
            id: "generated",
            status: "Enabled",
            filter: {},
            noncurrentVersionExpiration: { noncurrentDays: 30 },
          },
        ],
      }),
    ).toBe(true);
    expect(
      sameLifecycle(expected, {
        rules: [{ noncurrentVersionExpiration: { noncurrentDays: 7 } }],
      }),
    ).toBe(false);
    expect(sameLifecycle(undefined, null)).toBe(true);
    expect(sameLifecycle(undefined, { rules: ["odd"] })).toBe(false);
    expect(sameLifecycle(expected, null)).toBe(false);
  });
});

describe("bucket drift", () => {
  it("compares versioning and lifecycle when the database reports them", () => {
    expect(documents.versioning).toBe(true);
    expect(documents.lifecycle?.rules).toHaveLength(1);
    expect(documents.drift({ public: false })).toEqual([]);
    expect(
      documents
        .drift({ public: false, versioning: "SUSPENDED", lifecycle: null })
        .map((drift) => drift.field),
    ).toEqual(["versioning", "lifecycle"]);
    expect(
      documents.drift({
        public: false,
        versioning: "ENABLED",
        lifecycle: {
          rules: [
            {
              status: "Enabled",
              filter: {},
              noncurrentVersionExpiration: { noncurrentDays: 30 },
            },
          ],
        },
      }),
    ).toEqual([]);
    const plain = defineBucket({ id: "plain", path: "{file}" });
    expect(plain.versioning).toBe(false);
    expect(
      plain.drift({ public: false, versioning: "SUSPENDED", lifecycle: null }),
    ).toEqual([]);
    expect(
      plain.drift({ public: false, versioning: null, lifecycle: null }),
    ).toEqual([]);
    expect(
      plain.drift({ public: false, versioning: "ENABLED" })[0],
    ).toMatchObject({
      field: "versioning",
      message: 'Bucket "plain" versioning is ENABLED',
    });
  });
});

describe("versioned objects", () => {
  it("lists every version of one object, newest first", async () => {
    const { api, client } = fileApi({
      listV2: vi
        .fn()
        .mockResolvedValueOnce({
          data: {
            hasNext: true,
            nextCursor: "next",
            folders: [],
            objects: [
              {
                name: "o1/a.pdf",
                version: "v2",
                archived_at: null,
                is_delete_marker: false,
                created_at: "2026-02-01T00:00:00Z",
                metadata: { size: 4, mimetype: "application/pdf" },
              },
            ],
          },
          error: null,
        })
        .mockResolvedValueOnce({
          data: {
            hasNext: false,
            folders: [],
            objects: [
              {
                name: "o1/a.pdf",
                version: "v1",
                archived_at: "2026-02-01T00:00:00Z",
                created_at: "2026-01-01T00:00:00Z",
                metadata: null,
              },
              { name: "o1/a.pdf", version: null, metadata: null },
            ],
          },
          error: null,
        }),
    });
    const db = documents.connect(client);
    const versions = await db.versions({ organizationId: "o1", file: "a.pdf" });
    expect(versions.data).toEqual([
      {
        versionId: "v2",
        current: true,
        deleteMarker: false,
        size: 4,
        contentType: "application/pdf",
        createdAt: "2026-02-01T00:00:00Z",
        archivedAt: null,
      },
      {
        versionId: "v1",
        current: false,
        deleteMarker: false,
        createdAt: "2026-01-01T00:00:00Z",
        archivedAt: "2026-02-01T00:00:00Z",
      },
    ]);
    expect(api.listV2).toHaveBeenNthCalledWith(
      1,
      {
        prefix: "o1/a.pdf",
        exactMatch: true,
        noncurrentVersions: "include",
        deleteMarkers: "include",
        sortBy: { column: "created_at", order: "desc" },
      },
      {},
    );
    expect(api.listV2).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({ cursor: "next" }),
      {},
    );
  });

  it("maps list failures and checks paths first", async () => {
    const { client } = fileApi({
      listV2: vi.fn(async () => ({
        data: null,
        error: { name: "StorageApiError", message: "nope", statusCode: "403" },
      })),
    });
    const db = documents.connect(client);
    expect((await db.versions("o1/a.pdf")).error?.kind).toBe("forbidden");
    expect((await db.versions("not/a/match/x" as "o1/a.pdf")).error?.kind).toBe(
      "invalid_input",
    );
  });

  it("reads, copies, removes and signs one version", async () => {
    const { api, client } = fileApi();
    const db = documents.connect(client);
    await db.download("o1/a.pdf", { versionId: "v1" });
    expect(api.download).toHaveBeenCalledWith(
      "o1/a.pdf",
      { versionId: "v1" },
      {},
    );
    await db.download("o1/a.pdf");
    expect(api.download).toHaveBeenLastCalledWith("o1/a.pdf", {}, {});

    await db.copy("o1/a.pdf", "o1/restored.pdf", { versionId: "v1" });
    expect(api.copy).toHaveBeenCalledWith("o1/a.pdf", "o1/restored.pdf", {
      sourceVersionId: "v1",
    });
    await db.move("o1/a.pdf", "o1/b.pdf");
    expect(api.move).toHaveBeenCalledWith("o1/a.pdf", "o1/b.pdf", undefined);

    const removed = await db.removeVersions("o1/a.pdf", ["v1", "v0"]);
    expect(removed.data).toEqual(["v1", "v0"]);
    expect(api.remove).toHaveBeenCalledWith([
      { path: "o1/a.pdf", versionId: "v1" },
      { path: "o1/a.pdf", versionId: "v0" },
    ]);
    expect((await db.removeVersions("o1/a.pdf", [])).data).toEqual([]);
    expect(api.remove).toHaveBeenCalledTimes(1);

    await db.signedUrl("o1/a.pdf", { versionId: "v1", cacheNonce: "n" });
    expect(api.createSignedUrl).toHaveBeenCalledWith("o1/a.pdf", 3600, {
      cacheNonce: "n",
      versionId: "v1",
    });
    await db.signedUrls(["o1/a.pdf"], { cacheNonce: "n" });
    expect(api.createSignedUrls).toHaveBeenCalledWith(["o1/a.pdf"], 3600, {
      cacheNonce: "n",
    });
    db.publicUrl("o1/a.pdf", { cacheNonce: "n", download: true });
    expect(api.getPublicUrl).toHaveBeenCalledWith("o1/a.pdf", {
      download: true,
      cacheNonce: "n",
    });
  });

  it("keys cached signed URLs on the nonce and version", async () => {
    const { api, client } = fileApi();
    const db = documents.connect(client, { cacheSignedUrls: true });
    await db.signedUrl("o1/a.pdf", { cacheNonce: "1" });
    await db.signedUrl("o1/a.pdf", { cacheNonce: "1" });
    await db.signedUrl("o1/a.pdf", { cacheNonce: "2" });
    await db.signedUrl("o1/a.pdf", { versionId: "v1" });
    expect(api.createSignedUrl).toHaveBeenCalledTimes(3);
  });

  it("purges the CDN cache", async () => {
    const { api, client } = fileApi();
    const db = documents.connect(client);
    const signal = new AbortController().signal;
    expect(
      (await db.purgeCache("o1/a.pdf", { transformations: true, signal })).ok,
    ).toBe(true);
    expect(api.purgeCache).toHaveBeenCalledWith(
      "o1/a.pdf",
      { transformations: true },
      { signal },
    );
    const failing = fileApi({
      purgeCache: vi.fn(async () => ({
        data: null,
        error: {
          name: "StorageApiError",
          message:
            "Missing Required Parameter CDN_PURGE_ENDPOINT_URL is not set",
          status: 400,
          statusCode: "400",
          code: "MissingParameter",
        },
      })),
    });
    expect(
      (await documents.connect(failing.client).purgeCache("o1/a.pdf")).error
        ?.kind,
    ).toBe("invalid_request");
  });
});

describe("toVersion", () => {
  it("skips folders and marks delete markers", () => {
    expect(toVersion({ version: null })).toBeUndefined();
    expect(
      toVersion({ version: "v", is_delete_marker: true, archived_at: "t" }),
    ).toEqual({
      versionId: "v",
      current: false,
      deleteMarker: true,
      createdAt: null,
      archivedAt: "t",
    });
  });
});

describe("Storage feature errors", () => {
  it("maps disabled features and missing routes to unsupported", () => {
    expect(
      fromStorageError({
        name: "StorageApiError",
        message:
          "The feature object lifecycles is not enabled for this resource",
        status: 400,
        statusCode: "409",
        code: "FeatureNotEnabled",
      }).kind,
    ).toBe("unsupported");
    expect(
      fromStorageError({
        name: "StorageApiError",
        message: "Route GET:/iceberg/bucket not found",
        status: 404,
        statusCode: 404,
      }).kind,
    ).toBe("unsupported");
  });
});
