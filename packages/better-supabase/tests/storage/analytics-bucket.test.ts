import { describe, expect, it, vi } from "vitest";

import {
  defineAnalyticsBucket,
  type StorageClient,
} from "../../src/storage/index.ts";

function analyticsApi(names: string[]) {
  const catalog = { listNamespaces: vi.fn() };
  const analytics = {
    listBuckets: vi.fn(async (): Promise<unknown> => ({
      data: names.map((name) => ({ name, type: "ANALYTICS" })),
      error: null,
    })),
    createBucket: vi.fn(async (): Promise<unknown> => ({
      data: { name: "events" },
      error: null,
    })),
    from: vi.fn(() => catalog),
  };
  return {
    analytics,
    catalog,
    client: { storage: { analytics } } as unknown as StorageClient,
  };
}

const events = defineAnalyticsBucket({ id: "events" });

describe("defineAnalyticsBucket", () => {
  it("creates the bucket only when it is missing", async () => {
    const fresh = analyticsApi(["events-archive"]);
    expect((await events.connect(fresh.client).apply()).data).toEqual({
      created: true,
    });
    expect(fresh.analytics.listBuckets).toHaveBeenCalledWith({
      search: "events",
    });
    expect(fresh.analytics.createBucket).toHaveBeenCalledWith("events");

    const existing = analyticsApi(["events"]);
    expect((await events.connect(existing.client).apply()).data).toEqual({
      created: false,
    });
    expect(existing.analytics.createBucket).not.toHaveBeenCalled();
  });

  it("maps a stack without analytics buckets to unsupported", async () => {
    const { analytics, client } = analyticsApi([]);
    analytics.listBuckets.mockResolvedValueOnce({
      data: null,
      error: {
        name: "StorageApiError",
        message: "Route GET:/iceberg/bucket not found",
        status: 404,
        statusCode: 404,
      },
    });
    expect((await events.connect(client).apply()).error?.kind).toBe(
      "unsupported",
    );
    analytics.createBucket.mockResolvedValueOnce({
      data: null,
      error: { name: "StorageApiError", message: "no", statusCode: "403" },
    });
    expect((await events.connect(client).apply()).error?.kind).toBe(
      "forbidden",
    );
    analytics.listBuckets.mockRejectedValueOnce(new Error("boom"));
    expect((await events.connect(client).apply()).error?.kind).toBe(
      "unexpected",
    );
  });

  it("returns the Iceberg catalog of the bucket", () => {
    const { analytics, catalog, client } = analyticsApi([]);
    expect(events.connect(client).catalog()).toBe(catalog);
    expect(analytics.from).toHaveBeenCalledWith("events");
  });
});
