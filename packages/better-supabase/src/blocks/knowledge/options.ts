import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.knowledge.options`. */
export type KnowledgeSqlOptions = {
  readonly dimensions?: number;
  readonly type?: string;
  readonly textSearch?: string;
  readonly embedQueue?: string;
};

export const knowledgeSqlOptions: BlockOptionsSchema<KnowledgeSqlOptions> =
  blockOptions<KnowledgeSqlOptions>({
    dimensions: option.number({ default: 1536 }),
    type: option.string({ default: "vector" }),
    textSearch: option.string({ default: "simple" }),
    embedQueue: option.string({ default: "knowledge_embed" }),
  });
