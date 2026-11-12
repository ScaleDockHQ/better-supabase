import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { createKnowledge } from "./knowledge.ts";
import { knowledgeSqlOptions } from "./options.ts";

/** The `knowledge` block's manifest (ADR 0029). */
export const knowledgeBlock: BlockOf<
  "knowledge",
  typeof createKnowledge,
  Record<never, never>,
  { readonly files: "optional" }
> = defineBlock({
  name: "knowledge",
  sql: ["knowledge"],
  options: { knowledge: knowledgeSqlOptions },
  consumes: { files: "optional" },
  create: createKnowledge,
  category: "ai",
  entities: {
    knowledge_document: {
      mutability: "append-only",
      emits: { create: false, delete: false },
    },
  },
  description:
    "Documents and chunks for retrieval with an embedding and a tsvector each, scoped to an organization, agent, project, chat, user or record (subject) and grouped into collections with a visibility, a priority and grants, plus system documents shared with every tenant; hybrid search with reciprocal rank fusion, chunks that keep their embedding when unchanged, and an embed job per document when jobs is installed. With ai-files and jobs, queue_knowledge_file ingests a file through a job.",
  recipes: ["knowledge-upload"],
});
