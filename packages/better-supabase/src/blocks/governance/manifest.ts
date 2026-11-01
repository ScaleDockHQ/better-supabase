import type { BlockOf } from "../define-block.ts";

import { auditBlock } from "../audit/manifest.ts";
import { dataLifecycleBlock } from "../data-lifecycle/manifest.ts";
import { defineBlock } from "../define-block.ts";
import { fieldHistoryBlock } from "../field-history/manifest.ts";
import { createGovernance } from "./governance.ts";

/** The blocks `governance` is made of, by block name. */
export const governanceParts: {
  readonly audit: typeof auditBlock;
  readonly "field-history": typeof fieldHistoryBlock;
  readonly "data-lifecycle": typeof dataLifecycleBlock;
} = {
  audit: auditBlock,
  "field-history": fieldHistoryBlock,
  "data-lifecycle": dataLifecycleBlock,
};

export type GovernanceParts = typeof governanceParts;

/**
 * The `governance` composite (ADR 0177): the audit log, field history and data
 * lifecycle, for records that must stay accountable. It installs its parts and
 * sets their defaults; the parts stay ordinary blocks in the config.
 */
export const governanceBlock: BlockOf<"governance", typeof createGovernance> =
  defineBlock({
    name: "governance",
    composes: governanceParts,
    create: createGovernance,
    category: "admin",
  });
