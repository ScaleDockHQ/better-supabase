import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type {
  InvoiceFromTimeInput,
  TimeInvoice,
} from "../billable-time/index.ts";
import type { BlockContext } from "../create-blocks.ts";
import type { CompositeOptions } from "../define-block.ts";
import type { Timesheet } from "../time-tracking/index.ts";
import type { ProjectsParts } from "./manifest.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult as Async, ok } from "../../core/result.ts";

/** What `projects.approveAndInvoice` returns. */
export interface ApprovedAndInvoiced {
  readonly timesheet: Timesheet;
  readonly invoice: TimeInvoice;
}

/** The helpers `projects` adds over its parts. */
export interface Projects {
  /**
   * Approves the timesheet (`timeTracking.approve`), then invoices the time
   * `invoice` selects (`billableTime.invoice`). A refused approval invoices
   * nothing. A failed invoice returns its error and leaves the timesheet
   * approved, so retry it with `billableTime.invoice`.
   */
  approveAndInvoice(input: {
    timesheetId: string;
    decidedBy?: string | undefined;
    invoice?: InvoiceFromTimeInput | undefined;
  }): AsyncResult<ApprovedAndInvoiced>;
}

/** What the `projects` creator receives. */
export type ProjectsOptions = BlockContext &
  CompositeOptions<ProjectsParts> & {
    /** `before` and `after` hooks per method (ADR 0015). */
    readonly hooks?: NoInfer<BlockHooks<Projects>>;
    /** Receives the errors `after` hooks throw. Default: `console`. */
    readonly logger?: Logger;
  };

/** Creates the `projects` helpers over the clients of its parts. */
export function createProjects(options: ProjectsOptions): Projects {
  const { "time-tracking": timeTracking, "billable-time": billableTime } =
    options.parts;

  const client: Projects = {
    approveAndInvoice: ({ timesheetId, decidedBy, invoice }) =>
      Async.from(async () => {
        const timesheet = await timeTracking.approve({
          timesheetId,
          ...(decidedBy === undefined ? {} : { decidedBy }),
        });

        if (!timesheet.ok) {
          return timesheet;
        }

        const invoiced = await billableTime.invoice(invoice);

        return invoiced.ok
          ? ok({ timesheet: timesheet.data, invoice: invoiced.data })
          : invoiced;
      }),
  };

  return withBlockHooks(client, options.hooks, {
    block: "projects",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
