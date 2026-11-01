import type { BlockOf } from "../define-block.ts";

import { TICKETS } from "../../preset/preset-blocks.ts";
import { defineBlock } from "../define-block.ts";
import { inboxBlock } from "../inbox/manifest.ts";
import { knowledgeBlock } from "../knowledge/manifest.ts";
import { slaBlock } from "../sla/manifest.ts";
import { tasksBlock } from "../tasks/manifest.ts";
import { createSupport } from "./support.ts";

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
 * The `support` composite (ADR 0196): a shared inbox, tickets with SLAs and a
 * knowledge base. It installs its parts and sets their defaults; the parts stay
 * ordinary blocks in the config.
 */
export const supportBlock: BlockOf<"support", typeof createSupport> =
  defineBlock({
    name: "support",
    composes: supportParts,
    create: createSupport,
    defaults: TICKETS,
    category: "work",
  });
