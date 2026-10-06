import { describe, expect, it, vi } from "vitest";

import { defineBucket, type StorageClient } from "../../src/storage/index.ts";

const notFound = {
  name: "StorageApiError",
  message: "Bucket not found",
  status: 400,
  statusCode: "404",
};
const disabled = {
  name: "StorageApiError",
  message: "The feature object lifecycles is not enabled for this resource",
  status: 400,
  statusCode: "409",
  code: "FeatureNotEnabled",
};
const okMessage = { data: { message: "ok" }, error: null };

function bucketApi(found: { data: unknown; error: unknown }) {
  const api = {
    getBucket: vi.fn(async (): Promise<unknown> => found),
    createBucket: vi.fn(async (): Promise<unknown> => ({
      data: { name: "x" },
      error: null,
    })),
    updateBucket: vi.fn(async (): Promise<unknown> => okMessage),
    updateBucketLifecycle: vi.fn(async (): Promise<unknown> => ({
      data: {},
      error: null,
    })),
    deleteBucketLifecycle: vi.fn(async (): Promise<unknown> => okMessage),
  };
  return { api, client: { storage: api } as unknown as StorageClient };
}

const documents = defineBucket({
  id: "documents",
  path: "{organizationId}/{file}",
  fileSizeLimit: "10MiB",
  allowedMimeTypes: ["application/pdf"],
  versioning: true,
  lifecycle: {
    rules: [{ noncurrentVersionExpiration: { noncurrentDays: 30 } }],
  },
});

const plain = defineBucket({ id: "plain", path: "{file}", public: true });

describe("bucket.apply", () => {
  it("creates a missing bucket with versioning and its lifecycle", async () => {
    const { api, client } = bucketApi({ data: null, error: notFound });
    const applied = await documents.apply(client);
    expect(applied.data).toEqual({ created: true });
    expect(api.createBucket).toHaveBeenCalledWith("documents", {
      public: false,
      fileSizeLimit: 10_485_760,
      allowedMimeTypes: ["application/pdf"],
      versioningStatus: "ENABLED",
    });
    expect(api.updateBucketLifecycle).toHaveBeenCalledWith("documents", {
      rules: [
        {
          status: "Enabled",
          filter: {},
          noncurrentVersionExpiration: { noncurrentDays: 30 },
        },
      ],
    });
    expect(api.updateBucket).not.toHaveBeenCalled();
  });

  it("updates an existing bucket and removes a lifecycle it no longer has", async () => {
    const { api, client } = bucketApi({
      data: { id: "plain", versioning_status: "ENABLED" },
      error: null,
    });
    expect((await plain.apply(client)).data).toEqual({ created: false });
    expect(api.updateBucket).toHaveBeenCalledWith("plain", {
      public: true,
      fileSizeLimit: null,
      allowedMimeTypes: null,
      versioningStatus: "SUSPENDED",
    });
    expect(api.deleteBucketLifecycle).toHaveBeenCalledWith("plain");
  });

  it("leaves versioning alone on a bucket that never had it", async () => {
    const { api, client } = bucketApi({
      data: { id: "plain", versioning_status: "DISABLED" },
      error: null,
    });
    await plain.apply(client);
    expect(api.updateBucket).toHaveBeenCalledWith("plain", {
      public: true,
      fileSizeLimit: null,
      allowedMimeTypes: null,
    });
  });

  it("ignores a missing lifecycle or a project without lifecycles", async () => {
    for (const error of [
      { ...disabled },
      { ...notFound, code: "NoSuchLifecycleConfiguration" },
    ]) {
      const { api, client } = bucketApi({ data: { id: "plain" }, error: null });
      api.deleteBucketLifecycle.mockResolvedValueOnce({ data: null, error });
      expect((await plain.apply(client)).ok).toBe(true);
    }
  });

  it("reports the first failure", async () => {
    const forbidden = {
      name: "StorageApiError",
      message: "new row violates row-level security policy",
      statusCode: "403",
    };
    const cases: [
      string,
      (api: ReturnType<typeof bucketApi>["api"]) => void,
    ][] = [
      [
        "getBucket",
        (api) =>
          api.getBucket.mockResolvedValueOnce({ data: null, error: forbidden }),
      ],
      [
        "createBucket",
        (api) => {
          api.getBucket.mockResolvedValueOnce({ data: null, error: notFound });
          api.createBucket.mockResolvedValueOnce({
            data: null,
            error: forbidden,
          });
        },
      ],
      [
        "updateBucket",
        (api) =>
          api.updateBucket.mockResolvedValueOnce({
            data: null,
            error: forbidden,
          }),
      ],
      [
        "updateBucketLifecycle",
        (api) =>
          api.updateBucketLifecycle.mockResolvedValueOnce({
            data: null,
            error: disabled,
          }),
      ],
      [
        "deleteBucketLifecycle",
        (api) =>
          api.deleteBucketLifecycle.mockResolvedValueOnce({
            data: null,
            error: forbidden,
          }),
      ],
      [
        "throws",
        (api) =>
          api.getBucket.mockRejectedValueOnce(new TypeError("fetch failed")),
      ],
    ];
    const kinds: Record<string, string | undefined> = {};
    for (const [name, arrange] of cases) {
      const { api, client } = bucketApi({ data: { id: "x" }, error: null });
      arrange(api);
      const bucket = name === "deleteBucketLifecycle" ? plain : documents;
      kinds[name] = (await bucket.apply(client)).error?.kind;
    }
    expect(kinds).toEqual({
      getBucket: "forbidden",
      createBucket: "forbidden",
      updateBucket: "forbidden",
      updateBucketLifecycle: "unsupported",
      deleteBucketLifecycle: "forbidden",
      throws: "unexpected",
    });
  });
});
