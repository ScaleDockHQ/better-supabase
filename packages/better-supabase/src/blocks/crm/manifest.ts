import type { BlockOf } from "../define-block.ts";

import { activitiesBlock } from "../activities/manifest.ts";
import { assignmentBlock } from "../assignment/manifest.ts";
import { contactsBlock } from "../contacts/manifest.ts";
import { dealsBlock } from "../deals/manifest.ts";
import { defineBlock } from "../define-block.ts";
import { enrichmentBlock } from "../enrichment/manifest.ts";
import { forecastsBlock } from "../forecasts/manifest.ts";
import { goalsBlock } from "../goals/manifest.ts";
import { leadScoringBlock } from "../lead-scoring/manifest.ts";
import { mailSyncBlock } from "../mail-sync/manifest.ts";
import { pipelinesBlock } from "../pipelines/manifest.ts";
import { queueBlock } from "../queue/manifest.ts";
import { quotesBlock } from "../quotes/manifest.ts";
import { segmentsBlock } from "../segments/manifest.ts";
import { sequencesBlock } from "../sequences/manifest.ts";
import { createCrm } from "./crm.ts";

/** The blocks `crm` is made of, by block name. */
export const crmParts: {
  readonly contacts: typeof contactsBlock;
  readonly pipelines: typeof pipelinesBlock;
  readonly deals: typeof dealsBlock;
  readonly quotes: typeof quotesBlock;
  readonly goals: typeof goalsBlock;
  readonly activities: typeof activitiesBlock;
  readonly "mail-sync": typeof mailSyncBlock;
  readonly sequences: typeof sequencesBlock;
  readonly segments: typeof segmentsBlock;
  readonly assignment: typeof assignmentBlock;
  readonly enrichment: typeof enrichmentBlock;
  readonly forecasts: typeof forecastsBlock;
  readonly "lead-scoring": typeof leadScoringBlock;
  readonly queue: typeof queueBlock;
} = {
  contacts: contactsBlock,
  pipelines: pipelinesBlock,
  deals: dealsBlock,
  quotes: quotesBlock,
  goals: goalsBlock,
  activities: activitiesBlock,
  "mail-sync": mailSyncBlock,
  sequences: sequencesBlock,
  segments: segmentsBlock,
  assignment: assignmentBlock,
  enrichment: enrichmentBlock,
  forecasts: forecastsBlock,
  "lead-scoring": leadScoringBlock,
  queue: queueBlock,
};

export type CrmParts = typeof crmParts;

/**
 * The `crm` composite (ADR 0177): parties, pipelines, deals and quotes with
 * sales targets, engagements, synced mailboxes, email sequences, segments,
 * assignment queues, enrichment, forecasts and lead scoring. Add `sales` for
 * the order and invoice chain.
 */
export const crmBlock: BlockOf<"crm", typeof createCrm> = defineBlock({
  name: "crm",
  composes: crmParts,
  create: createCrm,
  category: "crm",
});
