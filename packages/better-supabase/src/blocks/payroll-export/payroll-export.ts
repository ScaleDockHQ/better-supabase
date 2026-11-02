import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { BlockOptions } from "../shared.ts";
import type { PayrollExportFile, PayrollExportFormat } from "./format.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  PAYROLL_LINE_KINDS,
  PAYROLL_LINE_UNITS,
  PAYROLL_RUN_STATUSES,
} from "../../sql/modules/payroll-export.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";
import { payrollFormatOf } from "./format.ts";

/** Where a payroll run stands: `exported` locks its lines. */
export type PayrollRunStatus = (typeof PAYROLL_RUN_STATUSES)[number];

/** What a payroll line counts: worked time, approved leave or scheduled shifts. */
export type PayrollLineKind = (typeof PAYROLL_LINE_KINDS)[number];

/** The unit of a payroll line's quantity. */
export type PayrollLineUnit = (typeof PAYROLL_LINE_UNITS)[number];

/** One person's total of one kind (and leave code) in a run. */
export interface PayrollLine {
  readonly id: string;
  /** The member, or none for an employee without an account. */
  readonly userId?: string;
  /** The employee, with the `employees` block. */
  readonly employeeId?: string;
  /** The name when the run was collected. */
  readonly employeeName?: string;
  readonly kind: PayrollLineKind;
  /** The leave type's key; none for worked and scheduled time. */
  readonly code?: string;
  /** Whether the leave type is paid; worked and scheduled time is. */
  readonly paid: boolean;
  readonly unit: PayrollLineUnit;
  /** Two decimals. */
  readonly quantity: number;
  /** How many entries, requests or assignments the line adds up. */
  readonly sourceCount: number;
}

/** A run without its lines. */
export interface PayrollRunSummary {
  readonly id: string;
  readonly organizationId: string;
  readonly periodFrom: Temporal.PlainDate;
  readonly periodTo: Temporal.PlainDate;
  readonly label?: string;
  readonly status: PayrollRunStatus;
  /** The `PayrollExportFormat` name, once exported. */
  readonly format?: string;
  /** The hex SHA-256 of the exported file. */
  readonly checksum?: string;
  readonly exportedAt?: Temporal.Instant;
  readonly exportedBy?: string;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  readonly lineCount: number;
}

export interface PayrollRun extends PayrollRunSummary {
  readonly lines: readonly PayrollLine[];
}

export interface PayrollRunInput {
  /** The first day, inclusive. */
  readonly from: Temporal.PlainDate;
  /** The last day, inclusive; at most 400 days after `from`. */
  readonly to: Temporal.PlainDate;
  readonly label?: string;
}

/** What `exportRun` returns: the locked run and the file to hand over. */
export interface PayrollExportResult {
  readonly run: PayrollRun;
  readonly file: PayrollExportFile;
}

export interface PayrollExport {
  /**
   * Creates a draft run and collects its lines from `options.sources`. A period
   * an exported run already covers fails with `PAYROLL_PERIOD_EXPORTED`.
   */
  create(input: PayrollRunInput): AsyncResult<PayrollRun>;
  /** Collects a draft run's lines again, for time that changed since. */
  refresh(runId: string): AsyncResult<PayrollRun>;
  get(runId: string): AsyncResult<PayrollRun | undefined>;
  /** The organization's runs, newest period first, without their lines. */
  list(): AsyncResult<readonly PayrollRunSummary[]>;
  /**
   * Renders the run with `format`, keeps the SHA-256 of the file on the run and
   * locks it. Exporting a locked run with the same file returns it again; a
   * different file fails with `PAYROLL_RUN_EXPORTED`.
   */
  exportRun(input: {
    runId: string;
    format: PayrollExportFormat;
  }): AsyncResult<PayrollExportResult>;
  /** Deletes a draft run. */
  delete(runId: string): AsyncResult<void>;
}

export interface PayrollExportOptions extends BlockOptions {
  readonly hooks?: NoInfer<BlockHooks<PayrollExport>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

const plainDate = (value: unknown): Temporal.PlainDate =>
  temporal().PlainDate.from(textOf(value));

function lineOf(value: unknown, fn: string): PayrollLine {
  const row = recordOf(value, fn);
  const userId = optionalText(row["userId"]);
  const employeeId = optionalText(row["employeeId"]);
  const employeeName = optionalText(row["employeeName"]);
  const code = optionalText(row["code"]);

  return {
    id: textOf(row["id"]),
    ...(userId ? { userId } : {}),
    ...(employeeId ? { employeeId } : {}),
    ...(employeeName ? { employeeName } : {}),
    kind: enumOrThrow(row["kind"], PAYROLL_LINE_KINDS, "payroll line kind"),
    ...(code ? { code } : {}),
    paid: row["paid"] === true,
    unit: enumOrThrow(row["unit"], PAYROLL_LINE_UNITS, "payroll line unit"),
    quantity: Number(row["quantity"]),
    sourceCount: Number(row["sourceCount"]),
  };
}

function summaryOf(value: unknown, fn: string): PayrollRunSummary {
  const row = recordOf(value, fn);
  const label = optionalText(row["label"]);
  const format = optionalText(row["format"]);
  const checksum = optionalText(row["checksum"]);
  const exportedAt = optionalInstant(row["exportedAt"]);
  const exportedBy = optionalText(row["exportedBy"]);
  const createdBy = optionalText(row["createdBy"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    periodFrom: plainDate(row["periodFrom"]),
    periodTo: plainDate(row["periodTo"]),
    ...(label ? { label } : {}),
    status: enumOrThrow(
      row["status"],
      PAYROLL_RUN_STATUSES,
      "payroll run status",
    ),
    ...(format ? { format } : {}),
    ...(checksum ? { checksum } : {}),
    ...(exportedAt ? { exportedAt } : {}),
    ...(exportedBy ? { exportedBy } : {}),
    ...(createdBy ? { createdBy } : {}),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    lineCount: Number(row["lineCount"]),
  };
}

function runOf(value: unknown, fn: string): PayrollRun {
  const row = recordOf(value, fn);

  return {
    ...summaryOf(row, fn),
    lines: recordsOf(row["lines"], fn).map((line) => lineOf(line, fn)),
  };
}

/** The hex SHA-256 of the file's text, through Web Crypto. */
async function checksumOf(body: string): Promise<string> {
  const digest = await globalThis.crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(body),
  );

  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

/** Creates the `payroll-export` client over a transport. */
export function createPayrollExport(
  options: PayrollExportOptions,
): PayrollExport {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const get = (runId: string): AsyncResult<PayrollRun | undefined> =>
    call("get_payroll_run", { run_id: runId }, (value) =>
      value === null ? undefined : runOf(value, "get_payroll_run"),
    );

  const client: PayrollExport = {
    create: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "create_payroll_run",
          {
            tenant: organizationId,
            input: {
              from: input.from.toString(),
              to: input.to.toString(),
              ...(input.label === undefined ? {} : { label: input.label }),
            },
          },
          (value) => runOf(value, "create_payroll_run"),
        ),
      ),
    refresh: (runId) =>
      call("refresh_payroll_run", { run_id: runId }, (value) =>
        runOf(value, "refresh_payroll_run"),
      ),
    get,
    list: () =>
      tenant().andThen((organizationId) =>
        call("list_payroll_runs", { tenant: organizationId }, (value) =>
          recordsOf(value, "list_payroll_runs").map((row) =>
            summaryOf(row, "list_payroll_runs"),
          ),
        ),
      ),
    exportRun: ({ runId, format }) =>
      AsyncResult.from(async () => {
        const checked = payrollFormatOf(format);
        const found = await get(runId);

        if (!found.ok) {
          return found;
        }

        if (found.data === undefined) {
          return err({
            kind: "not_found",
            message: "no such payroll run",
            status: 404,
            hint: "PAYROLL_RUN_NOT_FOUND",
          });
        }

        const file = await checked.render(found.data);
        const checksum = await checksumOf(file.body);

        const marked = await call(
          "mark_payroll_run_exported",
          { run_id: runId, format: checked.name, checksum },
          (value) => runOf(value, "mark_payroll_run_exported"),
        );

        return marked.ok ? ok({ run: marked.data, file }) : marked;
      }),
    delete: (runId) =>
      call("delete_payroll_run", { run_id: runId }, () => undefined),
  };

  return withBlockHooks(client, options.hooks, {
    block: "payroll-export",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
