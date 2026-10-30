import type { CaseKindDefinition } from "../../sql/modules/cases-sql.ts";
import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.cases.options`. */
export type CasesSqlOptions = {
  /**
   * The severities a case takes. Default `low`, `medium`, `high` and
   * `critical`.
   */
  readonly severities?: readonly string[];
  /**
   * Where a case comes from. Default `internal`, `customer`, `supplier`,
   * `inspection`, `regulator`, `employee` and `anonymous`.
   */
  readonly sources?: readonly string[];
  /**
   * The kinds each organization starts with: `{ key, name, prefix,
   * effectivenessAfterDays, requiresRootCause, requiresActions,
   * requiresEffectiveness, requiresRevisions }`. Default nonconformity (NC),
   * complaint (CMP), incident (INC), near miss (NM), observation (OBS),
   * improvement (IMP), change request (CHG, requires revisions) and audit
   * finding (FND).
   */
  readonly kinds?: readonly CaseKindDefinition[];
  /**
   * The kind `case_from_submission` opens when the answers name none. Default
   * `complaint`.
   */
  readonly intakeKind?: string;
  /** Extra columns on the cases table, set through `fields`. */
  readonly extraColumns?: ExtraColumns;
};

export const casesSqlOptions: BlockOptionsSchema<CasesSqlOptions> =
  blockOptions<CasesSqlOptions>({
    severities: option.strings(),
    sources: option.strings(),
    kinds: option.unknown<readonly CaseKindDefinition[]>(),
    intakeKind: option.string(),
    extraColumns: option.extraColumns(),
  });
