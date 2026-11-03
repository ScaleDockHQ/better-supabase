import { describe, expectTypeOf, it } from "vitest";

import type {
  Embedder,
  EmbedderV1,
  EmbedderV2,
  EmbedResult,
  KnowledgeHit,
} from "../../../src/blocks/knowledge/index.ts";

describe("knowledge types", () => {
  it("accepts both embedder versions", () => {
    expectTypeOf<EmbedderV1>().toExtend<Embedder>();
    expectTypeOf<EmbedderV2>().toExtend<Embedder>();
    expectTypeOf<EmbedderV2["apiVersion"]>().toEqualTypeOf<2>();
    expectTypeOf<EmbedResult["embeddings"]>().toEqualTypeOf<
      readonly (readonly number[])[]
    >();
  });

  it("types the hit ids", () => {
    expectTypeOf<KnowledgeHit["chunkId"]>().toBeString();
    expectTypeOf<KnowledgeHit["organizationId"]>().toEqualTypeOf<
      string | undefined
    >();
  });
});
