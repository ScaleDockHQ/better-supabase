import type { BlockContext } from "../create-blocks.ts";
import type { BlockOf, CompositeOptions } from "../define-block.ts";

import { TICKETS } from "../../preset/preset-blocks.ts";
import { defineBlock } from "../define-block.ts";
import { inboxBlock } from "../inbox/manifest.ts";
import { knowledgeBlock } from "../knowledge/manifest.ts";
import { slaBlock } from "../sla/manifest.ts";
import { tasksBlock } from "../tasks/manifest.ts";

/** The blocks `support` is made of, by block name. */
export const supportParts: {
  readonly inbox: typeof inboxBlock;
  readonly tasks: typeof tasksBlock;
  readonly sla: typeof slaBlock;
  readonly knowledge: typeof knowledgeBlock;
} = {
  inbox: inboxBlock,
  tasks: tasksBlock,
  sla: slaBlock,
  knowledge: knowledgeBlock,
};

export type SupportParts = typeof supportParts;

/**
 * The `support` composite (ADR 0177): a shared inbox, tickets with SLAs and a
 * knowledge base. It installs its parts and sets their defaults; the parts stay
 * ordinary blocks in the config.
 */
export const supportBlock: BlockOf<
  "support",
  (options: BlockContext & CompositeOptions<SupportParts>) => undefined
> = defineBlock({
  name: "support",
  composes: supportParts,
  defaults: TICKETS,
  category: "work",
});
