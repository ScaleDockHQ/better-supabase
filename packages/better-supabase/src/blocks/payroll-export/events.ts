import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** What every `payroll_run.*` event carries. */
export interface PayrollRunEventData {
  readonly organizationId: string;
  /** The payroll run. */
  readonly id: string;
  /** The first day of the period, as `YYYY-MM-DD`. */
  readonly periodFrom: string;
  /** The last day of the period, as `YYYY-MM-DD`. */
  readonly periodTo: string;
  /** Its status after the change. */
  readonly status: string;
  readonly lineCount: number;
}

/** `payroll_run.exported`: the run is locked behind a file. */
export interface PayrollRunExportedEventData extends PayrollRunEventData {
  /** The name of the `PayrollExportFormat` that rendered the file. */
  readonly format: string;
  /** The hex SHA-256 of the file. */
  readonly checksum: string;
}

/** The events of the `payroll-export` block: type to data. */
export type PayrollExportEvents = {
  readonly "payroll_run.created": PayrollRunEventData;
  readonly "payroll_run.exported": PayrollRunExportedEventData;
};

/**
 * The `payroll-export` block's event types, for its manifest and
 * `onBlockEvent`.
 */
export const payrollExportEvents: Events<PayrollExportEvents> = defineEvents({
  "payroll_run.created": event<PayrollRunEventData>(),
  "payroll_run.exported": event<PayrollRunExportedEventData>(),
});
