import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.payroll-export.options`. */
export type PayrollExportSqlOptions = {
  /** The IANA zone that assigns an entry or a shift to a day. Default `UTC`. */
  readonly timeZone?: string;
  /**
   * The blocks a run collects lines from: `time-tracking`, `leave` and
   * `shifts`. Default `["time-tracking", "leave"]`; scheduled shifts overlap
   * worked time, so they are opt-in.
   */
  readonly sources?: readonly string[];
};

export const payrollExportSqlOptions: BlockOptionsSchema<PayrollExportSqlOptions> =
  blockOptions<PayrollExportSqlOptions>({
    timeZone: option.string({ default: "UTC" }),
    sources: option.strings(),
  });
