import type { BlockOf } from "../define-block.ts";
import type { PipelinesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { pipelinesEvents } from "./events.ts";
import { pipelinesSqlOptions } from "./options.ts";
import { createPipelines } from "./pipelines.ts";

/** The `pipelines` block's manifest (ADR 0029). */
export const pipelinesBlock: BlockOf<
  "pipelines",
  typeof createPipelines,
  PipelinesEvents
> = defineBlock({
  name: "pipelines",
  sql: ["pipelines"],
  options: {
    pipelines: pipelinesSqlOptions,
  },
  events: pipelinesEvents,
  create: createPipelines,
  category: "work",
  recipes: ["deal-board"],
});
