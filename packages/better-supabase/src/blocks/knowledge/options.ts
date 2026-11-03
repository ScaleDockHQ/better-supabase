import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.knowledge.options`. */
export type KnowledgeSqlOptions = {
  readonly dimensions?: number;
  readonly type?: string;
  readonly textSearch?: string;
  readonly embedQueue?: string;
  readonly ingestQueue?: string;
  /** Sends pending chunks to an embedding worker with pg_net (ADR 0229). */
  readonly autoEmbed?: boolean;
};

export const knowledgeSqlOptions: BlockOptionsSchema<KnowledgeSqlOptions> =
  blockOptions<KnowledgeSqlOptions>({
    dimensions: option.number({ default: 1536 }),
    type: option.string({ default: "vector" }),
    textSearch: option.string({ default: "simple" }),
    embedQueue: option.string({ default: "knowledge_embed" }),
    ingestQueue: option.string({ default: "knowledge_ingest" }),
    autoEmbed: option.boolean({ default: false }),
  });
