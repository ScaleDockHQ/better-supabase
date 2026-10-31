import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.legal-entities.options`. */
export type LegalEntitiesSqlOptions = {
  /**
   * The modules whose tables get a nullable `legal_entity_id`: `invoices`,
   * `quotes`, `orders`, `numbering`, `accounting`, `inventory_locations` and
   * `settings`. Null means the organization's default legal entity.
   */
  readonly on?: readonly string[];
};

export const legalEntitiesSqlOptions: BlockOptionsSchema<LegalEntitiesSqlOptions> =
  blockOptions<LegalEntitiesSqlOptions>({ on: option.strings() });
