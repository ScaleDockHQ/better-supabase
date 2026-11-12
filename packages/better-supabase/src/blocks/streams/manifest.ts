import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { streamsSqlOptions } from "./options.ts";

/** The `streams` block's manifest (ADR 0029). */
export const streamsBlock: Block<"streams"> = defineBlock({
  name: "streams",
  sql: ["streams"],
  options: { streams: streamsSqlOptions },
  category: "automation",
  entities: { stream: { mutability: "read-only" } },
  description:
    "Ordered text chunks a writer appends and any reader resumes from an index: idempotent batches, a cancel flag the writer reads on its next append, owner reads through RLS, a payload-free Realtime ping on a private topic per stream, and a purge for expired streams.",
});
