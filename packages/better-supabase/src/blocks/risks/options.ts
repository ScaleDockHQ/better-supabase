import type { RiskMatrixDefinition } from "../../sql/modules/risks-sql.ts";
import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.risks.options`. */
export type RisksSqlOptions = {
  /**
   * The categories a risk takes. Default `quality`, `safety`, `environment`,
   * `security`, `compliance`, `operational`, `financial` and `strategic`.
   */
  readonly categories?: readonly string[];
  /**
   * The matrix each organization starts with: `{ key, name, likelihoodLevels,
   * impactLevels, bands, scoring }`. Default a 5 by 5 matrix scored as
   * likelihood times impact, banded low (1 to 4), medium (5 to 9), high (10 to 16)
   * and critical (17 to 25).
   */
  readonly defaultMatrix?: RiskMatrixDefinition;
  /** Extra columns on the risks table, set through `fields`. */
  readonly extraColumns?: ExtraColumns;
};

export const risksSqlOptions: BlockOptionsSchema<RisksSqlOptions> =
  blockOptions<RisksSqlOptions>({
    categories: option.strings(),
    defaultMatrix: option.unknown<RiskMatrixDefinition>(),
    extraColumns: option.extraColumns(),
  });
