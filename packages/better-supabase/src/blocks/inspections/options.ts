import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.inspections.options`. */
export type InspectionsSqlOptions = {
  /**
   * The kinds an inspection takes. Default `internal_audit`, `external_audit`,
   * `supplier_audit`, `certification_audit` and `inspection`.
   */
  readonly kinds?: readonly string[];
  /**
   * The types a finding takes. Default `major_nonconformity`,
   * `minor_nonconformity`, `observation`, `opportunity` and `positive`.
   */
  readonly findingTypes?: readonly string[];
  /**
   * The finding types that need a case before the inspection closes. Default
   * `major_nonconformity` and `minor_nonconformity`.
   */
  readonly caseFindingTypes?: readonly string[];
  /** Extra columns on the inspections table, set through `fields`. */
  readonly extraColumns?: ExtraColumns;
};

export const inspectionsSqlOptions: BlockOptionsSchema<InspectionsSqlOptions> =
  blockOptions<InspectionsSqlOptions>({
    kinds: option.strings(),
    findingTypes: option.strings(),
    caseFindingTypes: option.strings(),
    extraColumns: option.extraColumns(),
  });
