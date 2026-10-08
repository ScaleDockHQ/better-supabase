import type { Embedder } from "better-supabase/blocks/knowledge";

/** `sql.modules["vector-search"]` stores 1536 dimensions by default. */
const DIMENSIONS = 1536;

function hash(word: string): number {
  let value = 2166136261;
  for (const char of word) {
    value ^= char.codePointAt(0) ?? 0;
    value = Math.imul(value, 16777619);
  }
  return (value >>> 0) % DIMENSIONS;
}

/**
 * A deterministic bag-of-words embedder for running the sample without a
 * gateway key: texts that share words land close together.
 */
export const demoEmbedder: Embedder = {
  model: "demo/bag-of-words",
  embed: (values) =>
    Promise.resolve(
      values.map((value) => {
        const vector = Array.from<number>({ length: DIMENSIONS }).fill(0);
        for (const word of value.toLowerCase().match(/\p{L}{3,}/gu) ?? []) {
          const index = hash(word);
          vector[index] = (vector[index] ?? 0) + 1;
        }
        const norm = Math.hypot(...vector) || 1;
        return vector.map((x) => x / norm);
      }),
    ),
};
