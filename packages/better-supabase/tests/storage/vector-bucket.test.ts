import { describe, expect, it, vi } from "vitest";

import {
  defineVectorBucket,
  type StorageClient,
} from "../../src/storage/index.ts";

const missing = {
  name: "StorageVectorsApiError",
  message: 'resource "embeddings" not found',
  status: 404,
  statusCode: "404",
  code: "NotFoundException",
};
const empty = { data: {}, error: null };

const embeddings = defineVectorBucket({
  id: "embeddings",
  indexes: {
    documents: { dimension: 3 },
    images: {
      dimension: 2,
      distanceMetric: "euclidean",
      nonFilterableMetadataKeys: ["caption"],
    },
  },
});

function vectorsApi() {
  const index = {
    putVectors: vi.fn(async (_options: unknown) => empty),
    queryVectors: vi.fn(async () => ({
      data: {
        vectors: [{ key: "a", distance: 0, metadata: { kind: "x" } }],
      },
      error: null,
    })),
    getVectors: vi.fn(async () => ({
      data: { vectors: [{ key: "a", data: { float32: [1, 0, 0] } }] },
      error: null,
    })),
    deleteVectors: vi.fn(async () => empty),
  };
  const scope = {
    getIndex: vi.fn(async (_name: string): Promise<unknown> => ({
      data: null,
      error: missing,
    })),
    createIndex: vi.fn(async () => empty),
    index: vi.fn(() => index),
  };
  const vectors = {
    getBucket: vi.fn(async (): Promise<unknown> => ({
      data: { vectorBucket: { vectorBucketName: "embeddings" } },
      error: null,
    })),
    createBucket: vi.fn(async () => empty),
    from: vi.fn(() => scope),
  };
  return {
    vectors,
    scope,
    index,
    client: { storage: { vectors } } as unknown as StorageClient,
  };
}

describe("defineVectorBucket", () => {
  it("refuses an index without a whole, positive dimension", () => {
    expect(() =>
      defineVectorBucket({ id: "v", indexes: { a: { dimension: 0 } } }),
    ).toThrow('index "a" needs a whole, positive dimension');
  });

  it("creates the bucket and the missing indexes", async () => {
    const { vectors, scope, client } = vectorsApi();
    vectors.getBucket.mockResolvedValueOnce({ data: null, error: missing });
    scope.getIndex.mockImplementation(async (name: string) =>
      name === "documents"
        ? {
            data: {
              index: {
                indexName: "documents",
                dimension: 3,
                distanceMetric: "cosine",
              },
            },
            error: null,
          }
        : { data: null, error: missing },
    );
    const applied = await embeddings.connect(client).apply();
    expect(applied.data).toEqual({ created: ["images"] });
    expect(vectors.createBucket).toHaveBeenCalledWith("embeddings");
    expect(scope.createIndex).toHaveBeenCalledWith({
      indexName: "images",
      dataType: "float32",
      dimension: 2,
      distanceMetric: "euclidean",
      metadataConfiguration: { nonFilterableMetadataKeys: ["caption"] },
    });
  });

  it("refuses an existing index with another shape", async () => {
    const { scope, client } = vectorsApi();
    scope.getIndex.mockResolvedValueOnce({
      data: { index: { dimension: 1536, distanceMetric: "cosine" } },
      error: null,
    });
    const applied = await embeddings.connect(client).apply();
    expect(applied.error).toMatchObject({
      kind: "conflict",
      message:
        'Vector index "documents" has dimension 1536 and metric cosine, not 3 and cosine',
    });
  });

  it("reports bucket and index failures", async () => {
    const forbidden = {
      name: "StorageVectorsApiError",
      message: "no",
      statusCode: "403",
    };
    const one = vectorsApi();
    one.vectors.getBucket.mockResolvedValueOnce({
      data: null,
      error: forbidden,
    });
    expect((await embeddings.connect(one.client).apply()).error?.kind).toBe(
      "forbidden",
    );
    const two = vectorsApi();
    two.scope.getIndex.mockResolvedValueOnce({ data: null, error: forbidden });
    expect((await embeddings.connect(two.client).apply()).error?.kind).toBe(
      "forbidden",
    );
    const three = vectorsApi();
    three.vectors.getBucket.mockRejectedValueOnce(
      Object.assign(new Error("fetch failed"), { name: "StorageUnknownError" }),
    );
    expect((await embeddings.connect(three.client).apply()).error?.kind).toBe(
      "network",
    );
  });

  it("puts, queries, gets and removes vectors of one index", async () => {
    const { scope, index, client } = vectorsApi();
    const docs = embeddings
      .connect(client)
      .index<{ kind: string }>("documents");
    expect(docs).toMatchObject({ name: "documents", dimension: 3 });

    const records = Array.from({ length: 501 }, (_, i) => ({
      key: `k${String(i)}`,
      vector: [i, 0, 0],
      ...(i === 0 ? { metadata: { kind: "x" } } : {}),
    }));
    expect((await docs.put(records)).data).toBe(501);
    expect(index.putVectors).toHaveBeenCalledTimes(2);
    expect(index.putVectors.mock.calls[0]?.[0]).toMatchObject({
      vectors: expect.arrayContaining([
        { key: "k0", data: { float32: [0, 0, 0] }, metadata: { kind: "x" } },
      ]),
    });
    expect(scope.index).toHaveBeenCalledWith("documents");

    const hits = await docs.query([1, 0, 0], {
      topK: 2,
      filter: { kind: "x" },
    });
    expect(hits.data).toEqual([
      { key: "a", distance: 0, metadata: { kind: "x" } },
    ]);
    expect(index.queryVectors).toHaveBeenCalledWith({
      queryVector: { float32: [1, 0, 0] },
      topK: 2,
      returnDistance: true,
      returnMetadata: true,
      filter: { kind: "x" },
    });

    const got = await docs.get(["a", "zz"], { vector: true });
    expect(got.data).toEqual([{ key: "a", vector: [1, 0, 0] }]);
    expect(index.getVectors).toHaveBeenCalledWith({
      keys: ["a", "zz"],
      returnMetadata: true,
      returnData: true,
    });

    expect((await docs.remove(["a"])).data).toEqual(["a"]);
    expect(index.deleteVectors).toHaveBeenCalledWith({ keys: ["a"] });
  });

  it("gets batches four at a time and keeps the key order", async () => {
    const { index, client } = vectorsApi();
    let active = 0;
    let peak = 0;
    index.getVectors.mockImplementation((async (options: {
      keys: string[];
    }) => {
      active++;
      peak = Math.max(peak, active);
      // Later batches answer first.
      await new Promise((resolve) => {
        setTimeout(resolve, 20 - Number(options.keys[0]!.slice(1)) / 100);
      });
      active--;
      return {
        data: { vectors: options.keys.map((key) => ({ key })) },
        error: null,
      };
    }) as never);
    const keys = Array.from({ length: 600 }, (_, i) => `k${String(i)}`);
    const got = await embeddings.connect(client).index("documents").get(keys);
    expect(got.data?.map((found) => found.key)).toEqual(keys);
    expect(index.getVectors).toHaveBeenCalledTimes(6);
    expect(peak).toBe(4);
  });

  it("checks dimensions before Storage does", async () => {
    const { index, client } = vectorsApi();
    const docs = embeddings.connect(client).index("documents");
    expect(
      (await docs.put([{ key: "bad", vector: [1, 2] }])).error,
    ).toMatchObject({
      kind: "invalid_input",
      message: 'Vector "bad" has 2 values; index "documents" takes 3',
    });
    expect((await docs.query([1])).error?.message).toBe(
      'The query vector has 1 values; index "documents" takes 3',
    );
    expect(index.putVectors).not.toHaveBeenCalled();
    expect(index.queryVectors).not.toHaveBeenCalled();
  });

  it("maps index call failures", async () => {
    const failure = {
      data: null,
      error: {
        name: "StorageVectorsApiError",
        message: "boom",
        statusCode: "500",
      },
    };
    const { index, client } = vectorsApi();
    index.putVectors.mockResolvedValueOnce(failure as never);
    index.queryVectors.mockResolvedValueOnce(failure as never);
    index.getVectors.mockResolvedValueOnce(failure as never);
    index.deleteVectors.mockResolvedValueOnce(failure as never);
    const docs = embeddings.connect(client).index("documents");
    const kinds = [
      (await docs.put([{ key: "a", vector: [1, 0, 0] }])).error?.kind,
      (await docs.query([1, 0, 0])).error?.kind,
      (await docs.get(["a"])).error?.kind,
      (await docs.remove(["a"])).error?.kind,
    ];
    expect(kinds).toEqual(["network", "network", "network", "network"]);
  });
});
