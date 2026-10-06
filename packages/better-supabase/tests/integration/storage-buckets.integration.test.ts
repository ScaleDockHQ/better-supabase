import { createClient } from "@supabase/supabase-js";
import { afterAll, describe, expect, it } from "vitest";

import { defineBucket, defineVectorBucket } from "../../src/storage/index.ts";

const url = process.env["SUPABASE_URL"] ?? "http://127.0.0.1:55421";
const secretKey =
  process.env["SUPABASE_SECRET_KEY"] ??
  "sb_secret_N7UND0UgjKTVK-Uodkm0Hg_xSvEMPvz";

async function reachable(): Promise<boolean> {
  try {
    const response = await fetch(`${url}/storage/v1/status`, {
      signal: AbortSignal.timeout(1000),
    });
    return response.ok;
  } catch {
    return false;
  }
}

const live = await reachable();
const admin = createClient(url, secretKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});
const suffix = String(Date.now());

describe.skipIf(!live)("Storage buckets through the API", () => {
  const reports = defineBucket({
    id: `bs-it-apply-${suffix}`,
    path: "{organizationId}/{file}",
    fileSizeLimit: "1MiB",
    allowedMimeTypes: ["application/pdf"],
  });
  const embeddings = defineVectorBucket({
    id: `bs-it-vectors-${suffix}`,
    indexes: { documents: { dimension: 3 } },
  });

  afterAll(async () => {
    await admin.storage.deleteBucket(reports.id);
    const scope = admin.storage.vectors.from(embeddings.id);
    await scope.deleteIndex("documents");
    await admin.storage.vectors.deleteBucket(embeddings.id);
  });

  it("creates, then updates, a bucket with apply()", async () => {
    expect((await reports.apply(admin)).data).toEqual({ created: true });
    expect((await reports.apply(admin)).data).toEqual({ created: false });
    const { data } = await admin.storage.getBucket(reports.id);
    expect(data).toMatchObject({
      public: false,
      file_size_limit: 1_048_576,
      allowed_mime_types: ["application/pdf"],
    });
  });

  it("creates a vector bucket and searches it", async () => {
    const connected = embeddings.connect(admin);
    expect((await connected.apply()).data).toEqual({ created: ["documents"] });
    expect((await connected.apply()).data).toEqual({ created: [] });
    const docs = connected.index<{ kind: string }>("documents");
    expect(
      (
        await docs.put([
          { key: "a", vector: [1, 0, 0], metadata: { kind: "pdf" } },
          { key: "b", vector: [0, 1, 0], metadata: { kind: "doc" } },
        ])
      ).data,
    ).toBe(2);
    const hits = await docs.query([1, 0, 0], { topK: 2 });
    expect(hits.data?.map((hit) => hit.key)).toEqual(["a", "b"]);
    expect(hits.data?.[0]?.metadata).toEqual({ kind: "pdf" });
    expect((await docs.get(["b"], { vector: true })).data).toEqual([
      { key: "b", metadata: { kind: "doc" }, vector: [0, 1, 0] },
    ]);
    expect((await docs.remove(["a", "b"])).ok).toBe(true);
    expect((await docs.get(["a"])).data).toEqual([]);
  });
});
