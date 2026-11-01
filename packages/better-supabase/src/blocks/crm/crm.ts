import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { BlockContext } from "../create-blocks.ts";
import type { CompositeOptions } from "../define-block.ts";
import type { Sales } from "../sales/index.ts";
import type { CrmParts } from "./manifest.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { createDealClosers } from "../sales/index.ts";

/**
 * The helpers `crm` adds over its parts: the ones `sales` shares for closing
 * deals.
 */
export type Crm = Pick<Sales, "closeWon" | "closeLost">;

/** What the `crm` creator receives. */
export type CrmOptions = BlockContext &
  CompositeOptions<CrmParts> & {
    /** `before` and `after` hooks per method (ADR 0015). */
    readonly hooks?: NoInfer<BlockHooks<Crm>>;
    /** Receives the errors `after` hooks throw. Default: `console`. */
    readonly logger?: Logger;
  };

/** Creates the `crm` helpers over the clients of its parts. */
export function createCrm(options: CrmOptions): Crm {
  const { deals, quotes } = options.parts;

  return withBlockHooks(createDealClosers({ deals, quotes }), options.hooks, {
    block: "crm",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
