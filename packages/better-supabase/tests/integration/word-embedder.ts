import type { Embedder } from "../../src/blocks/knowledge/index.ts";

/** A bag of words hashed into 1536 dimensions, so equal words land close. */
export function wordEmbedder(model = "words-v1"): Embedder & {
  calls: number;
} {
  const embedder = {
    model,
    calls: 0,
    embed(values: readonly string[]) {
      embedder.calls += 1;
      return Promise.resolve(
        values.map((value) => {
          const vector = Array.from({ length: 1536 }, () => 0);
          for (const word of value.toLowerCase().match(/[a-z]+/g) ?? []) {
            let hash = 0;
            for (const char of word)
              hash = (hash * 31 + (char.codePointAt(0) ?? 0)) % 1536;
            vector[hash] = (vector[hash] ?? 0) + 1;
          }
          const norm = Math.hypot(...vector) || 1;
          return vector.map((x) => x / norm);
        }),
      );
    },
  };
  return embedder;
}
