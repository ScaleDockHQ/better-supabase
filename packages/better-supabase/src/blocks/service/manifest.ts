import type { BlockOf } from "../define-block.ts";

import { assetsBlock } from "../assets/manifest.ts";
import { casesBlock } from "../cases/manifest.ts";
import { defineBlock } from "../define-block.ts";
import { dispatchBlock } from "../dispatch/manifest.ts";
import { inventoryBlock } from "../inventory/manifest.ts";
import { maintenanceBlock } from "../maintenance/manifest.ts";
import { slaBlock } from "../sla/manifest.ts";
import { createService } from "./service.ts";

/** The blocks `service` is made of, by block name. */
export const serviceParts: {
  readonly dispatch: typeof dispatchBlock;
  readonly maintenance: typeof maintenanceBlock;
  readonly assets: typeof assetsBlock;
  readonly cases: typeof casesBlock;
  readonly inventory: typeof inventoryBlock;
  readonly sla: typeof slaBlock;
} = {
  dispatch: dispatchBlock,
  maintenance: maintenanceBlock,
  assets: assetsBlock,
  cases: casesBlock,
  inventory: inventoryBlock,
  sla: slaBlock,
};

export type ServiceParts = typeof serviceParts;

/**
 * The `service` composite (ADR 0177): dispatch, maintenance plans, assets,
 * cases, stock and SLAs for field service. It installs its parts and sets their
 * defaults; the parts stay ordinary blocks in the config.
 */
export const serviceBlock: BlockOf<"service", typeof createService> =
  defineBlock({
    name: "service",
    composes: serviceParts,
    create: createService,
    category: "work",
  });
