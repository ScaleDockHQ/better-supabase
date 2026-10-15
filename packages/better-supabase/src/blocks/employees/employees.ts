import type { SubjectConfig } from "../../config/types/subjects.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";

import { blockFields, type FieldsOf } from "../../core/block-fields.ts";
import { DEFAULT_BLOCK_SCHEMA } from "../../core/block-helpers.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult, ok } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  big,
  compact,
  plainDate,
  type RecordRef,
  refOf,
} from "../sales-shared.ts";
import {
  applyTemporal,
  blockCall,
  type BlockTemporalOptions,
  enumOrThrow,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";

export type EmployeeStatus =
  | "preboarding"
  | "active"
  | "on_leave"
  | "offboarded";
export type SalaryPeriod = "hour" | "week" | "month" | "year";

const STATUSES: readonly EmployeeStatus[] = [
  "preboarding",
  "active",
  "on_leave",
  "offboarded",
];
const PERIODS: readonly SalaryPeriod[] = ["hour", "week", "month", "year"];

const COLUMNS = new Set([
  "id",
  "tenant_id",
  "user_id",
  "name",
  "email",
  "job_title",
  "team_id",
  "manager_id",
  "employment_type",
  "status",
  "start_date",
  "end_date",
  "offboard_reason",
  "origin_type",
  "origin_id",
  "created_by",
  "created_at",
  "updated_at",
  "depth",
  "direct_reports",
]);

/** An employee. `F` types the extra columns the `fields` schema describes. */
export interface Employee<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  readonly name: string;
  readonly email?: string;
  /** The account, when the employee has one; contractors and interns often don't. */
  readonly userId?: string;
  readonly jobTitle?: string;
  readonly teamId?: string;
  readonly managerId?: string;
  readonly employmentType?: string;
  readonly status: EmployeeStatus;
  readonly startDate?: Temporal.PlainDate;
  readonly endDate?: Temporal.PlainDate;
  readonly offboardReason?: string;
  /** The record it was made from, such as `{ type: "application", id }`. */
  readonly origin?: RecordRef;
  readonly createdAt?: Temporal.Instant;
  /** The app's extra columns (`options.extraColumns`), by column name. */
  readonly fields: Readonly<Record<string, unknown>> & F;
}

/** An employee in the org chart or a manager's reports. */
export interface OrgChartEntry<
  F extends object = Record<never, never>,
> extends Employee<F> {
  /** 0 for a root of the chart, 1 for a direct report. */
  readonly depth: number;
  readonly directReports: number;
}

export interface EmployeeInput<F extends object = Record<never, never>> {
  readonly name: string;
  readonly email?: string;
  readonly userId?: string;
  readonly jobTitle?: string;
  readonly teamId?: string;
  readonly managerId?: string;
  /** One of `options.employmentTypes`; the first one by default. */
  readonly employmentType?: string;
  /** Preboarding before the start date and active from it, by default. */
  readonly status?: Exclude<EmployeeStatus, "offboarded">;
  readonly startDate?: Temporal.PlainDate;
  readonly endDate?: Temporal.PlainDate;
  /** With an origin, creating again returns the same employee. */
  readonly origin?: RecordRef;
  readonly fields?: Partial<F> & Readonly<Record<string, unknown>>;
}

export type EmployeeField =
  | "name"
  | "email"
  | "userId"
  | "jobTitle"
  | "teamId"
  | "managerId"
  | "employmentType"
  | "status"
  | "startDate"
  | "endDate";

/** One cell edit: a field above, or an extra column by name. `null` clears it. */
export interface EmployeeChange {
  readonly employeeId: string;
  readonly field: EmployeeField | (string & {});
  readonly value: unknown;
}

export interface EmployeeChangeResult {
  readonly accepted: readonly {
    readonly employeeId: string;
    readonly field: string;
  }[];
  /** Each refused change, with the error hint and message. Others still applied. */
  readonly rejected: readonly {
    readonly employeeId: string;
    readonly field: string;
    readonly hint?: string;
    readonly reason: string;
  }[];
}

export interface EmergencyContact {
  readonly name: string;
  readonly phone?: string;
  readonly relation?: string;
}

export interface PrivateDetails {
  readonly employeeId: string;
  readonly nationalId?: string;
  readonly iban?: string;
  readonly birthDate?: Temporal.PlainDate;
  readonly personalEmail?: string;
  readonly phone?: string;
  readonly address?: Readonly<Record<string, unknown>>;
  readonly emergencyContacts: readonly EmergencyContact[];
  /** Set on offboarding, so an anonymize rule can start from it. */
  readonly offboardedAt?: Temporal.Instant;
  readonly anonymizedAt?: Temporal.Instant;
}

/** The details to save. Left out keeps the stored value; `null` clears it. */
export interface PrivateDetailsInput {
  readonly nationalId?: string | null;
  readonly iban?: string | null;
  readonly birthDate?: Temporal.PlainDate | null;
  readonly personalEmail?: string | null;
  readonly phone?: string | null;
  readonly address?: Readonly<Record<string, unknown>> | null;
  readonly emergencyContacts?: readonly EmergencyContact[] | null;
}

/** A contract. Salary is minor units of `currency`. */
export interface Contract {
  readonly id: string;
  readonly employeeId: string;
  readonly startsOn: Temporal.PlainDate;
  readonly endsOn?: Temporal.PlainDate;
  readonly hoursPerWeek?: number;
  readonly salary?: bigint;
  readonly currency?: string;
  readonly salaryPeriod?: SalaryPeriod;
  readonly note?: string;
}

export interface ContractInput {
  readonly startsOn: Temporal.PlainDate;
  readonly endsOn?: Temporal.PlainDate;
  readonly hoursPerWeek?: number;
  readonly salary?: bigint;
  readonly currency?: string;
  readonly salaryPeriod?: SalaryPeriod;
  readonly note?: string;
}

export interface Employees<F extends object = Record<never, never>> {
  create(
    organizationId: string,
    input: EmployeeInput<F>,
  ): AsyncResult<Employee<F>>;
  /** Applies each change on its own; one that fails doesn't stop the others. */
  update(changes: readonly EmployeeChange[]): AsyncResult<EmployeeChangeResult>;
  /** Sets the end date (today by default) and moves the reports to the employee's manager. */
  offboard(
    employeeId: string,
    options?: {
      readonly endDate?: Temporal.PlainDate;
      readonly reason?: string;
    },
  ): AsyncResult<Employee<F>>;
  /** The chart under `rootId`, or under everyone without a manager. */
  orgChart(
    organizationId: string,
    rootId?: string,
  ): AsyncResult<readonly OrgChartEntry<F>[]>;
  /** Direct reports, or everyone under the manager with `indirect`. */
  reportsOf(
    managerId: string,
    options?: { readonly indirect?: boolean },
  ): AsyncResult<readonly OrgChartEntry<F>[]>;
  /**
   * The employee for a hired application (the hiring module), in
   * preboarding, made once. `overrides` replaces what the candidate and
   * the job give.
   */
  fromApplication(
    applicationId: string,
    overrides?: Partial<EmployeeInput<F>>,
  ): AsyncResult<Employee<F>>;
  /** Needs employees.view_sensitive, or being the employee. */
  privateDetails(employeeId: string): AsyncResult<PrivateDetails | undefined>;
  savePrivateDetails(
    employeeId: string,
    input: PrivateDetailsInput,
  ): AsyncResult<PrivateDetails>;
  /** The newest first. */
  contracts(employeeId: string): AsyncResult<readonly Contract[]>;
  /** Starts after the latest contract, which ends the day before. */
  addContract(employeeId: string, input: ContractInput): AsyncResult<Contract>;
}

export interface EmployeesOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  /**
   * A Standard Schema for the extra columns
   * (`blocks.employees.options.extraColumns`), keyed by column name.
   * It types and parses `fields` on reads and validates them on writes.
   */
  readonly fields?: S;
  readonly hooks?: NoInfer<BlockHooks<Employees<FieldsOf<S>>>>;
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

function argOf(value: unknown): unknown {
  if (typeof value === "bigint") return value.toString();
  if (value instanceof temporal().PlainDate) return value.toString();
  return value;
}

const argsOf = (input: object): Record<string, unknown> =>
  Object.fromEntries(
    Object.entries(input).map(([key, value]) => [key, argOf(value)]),
  );

function requiredDate(value: unknown, field: string): Temporal.PlainDate {
  const date = plainDate(value);
  if (date === undefined) throw new TypeError(`${field} is missing`);
  return date;
}

const num = (value: unknown): number | undefined =>
  value === null || value === undefined ? undefined : Number(value);

function employeeOf(value: unknown): Employee {
  const row = recordOf(value, "employee");
  return compact<Employee>({
    id: textOf(row["id"]),
    organizationId: textOf(row["tenant_id"]),
    name: textOf(row["name"]),
    email: optionalText(row["email"]),
    userId: optionalText(row["user_id"]),
    jobTitle: optionalText(row["job_title"]),
    teamId: optionalText(row["team_id"]),
    managerId: optionalText(row["manager_id"]),
    employmentType: optionalText(row["employment_type"]),
    status: enumOrThrow(row["status"], STATUSES, "employee status"),
    startDate: plainDate(row["start_date"]),
    endDate: plainDate(row["end_date"]),
    offboardReason: optionalText(row["offboard_reason"]),
    origin: refOf(row["origin_type"], row["origin_id"]),
    createdAt: optionalInstant(row["created_at"]),
    fields: Object.fromEntries(
      Object.entries(row).filter(([key]) => !COLUMNS.has(key)),
    ),
  });
}

function contactsOf(value: unknown): readonly EmergencyContact[] {
  return Array.isArray(value)
    ? value.filter(isRecord).map((item) =>
        compact<EmergencyContact>({
          name: textOf(item["name"]),
          phone: optionalText(item["phone"]),
          relation: optionalText(item["relation"]),
        }),
      )
    : [];
}

function privateOf(value: unknown): PrivateDetails {
  const row = recordOf(value, "private details");
  const address = row["address"];
  return compact<PrivateDetails>({
    employeeId: textOf(row["employee_id"]),
    nationalId: optionalText(row["national_id"]),
    iban: optionalText(row["iban"]),
    birthDate: plainDate(row["birth_date"]),
    personalEmail: optionalText(row["personal_email"]),
    phone: optionalText(row["phone"]),
    address: isRecord(address) ? address : undefined,
    emergencyContacts: contactsOf(row["emergency_contacts"]),
    offboardedAt: optionalInstant(row["offboarded_at"]),
    anonymizedAt: optionalInstant(row["anonymized_at"]),
  });
}

function contractOf(value: unknown): Contract {
  const row = recordOf(value, "contract");
  const period = row["salary_period"];
  return compact<Contract>({
    id: textOf(row["id"]),
    employeeId: textOf(row["employee_id"]),
    startsOn: requiredDate(row["starts_on"], "startsOn"),
    endsOn: plainDate(row["ends_on"]),
    hoursPerWeek: num(row["hours_per_week"]),
    salary:
      row["salary"] === null || row["salary"] === undefined
        ? undefined
        : big(row["salary"]),
    currency: optionalText(row["currency"]),
    salaryPeriod:
      period === null || period === undefined
        ? undefined
        : enumOrThrow(period, PERIODS, "salary period"),
    note: optionalText(row["note"]),
  });
}

const BUILT_IN: ReadonlySet<string> = new Set<EmployeeField>([
  "name",
  "email",
  "userId",
  "jobTitle",
  "teamId",
  "managerId",
  "employmentType",
  "status",
  "startDate",
  "endDate",
]);

/**
 * The employees block: the people an organization employs, their manager,
 * team and status, the org chart, offboarding, and private details and
 * contracts behind employees.view_sensitive.
 */
export function createEmployees<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: EmployeesOptions<S>): Employees<FieldsOf<S>> {
  type F = FieldsOf<S>;
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const fields = blockFields<F>(options.fields, "employee fields");
  const parsed = (employee: Employee): AsyncResult<Employee<F>> =>
    AsyncResult.from(() => fields.read(employee.fields)).map((value) => ({
      ...employee,
      fields: value,
    }));
  const entries = (value: unknown, name: string) =>
    recordsOf(value, name).map((row) => ({
      employee: employeeOf(row),
      depth: num(row["depth"]) ?? 0,
      directReports: num(row["direct_reports"]) ?? 0,
    }));
  const chart = (
    fn: string,
    args: Record<string, unknown>,
  ): AsyncResult<readonly OrgChartEntry<F>[]> =>
    call(fn, args, (value) => entries(value, fn)).andThen((rows) =>
      AsyncResult.from(async () => {
        const out: OrgChartEntry<F>[] = [];
        for (const row of rows) {
          const read = await parsed(row.employee);
          if (!read.ok) return read;
          out.push({
            ...read.data,
            depth: row.depth,
            directReports: row.directReports,
          });
        }
        return ok(out);
      }),
    );
  const attrsOf = (input: Partial<EmployeeInput<F>>) =>
    AsyncResult.from(() => fields.write({ ...input.fields })).map((extra) => {
      const { fields: _fields, ...rest } = input;
      return { ...argsOf(rest), ...argsOf(extra) };
    });
  const client: Employees<F> = {
    create: (organizationId, input) =>
      attrsOf(input)
        .andThen((attrs) =>
          call(
            "create_employee",
            { tenant: organizationId, attrs },
            employeeOf,
          ),
        )
        .andThen(parsed),
    update: (changes) =>
      AsyncResult.from(async () => {
        for (const change of changes) {
          if (BUILT_IN.has(change.field)) continue;
          const valid = await fields.write({ [change.field]: change.value });
          if (!valid.ok) return valid;
        }
        return ok(changes);
      }).andThen((checked) =>
        call(
          "update_employees",
          {
            changes: checked.map((change) => ({
              employeeId: change.employeeId,
              field: change.field,
              value: argOf(change.value),
            })),
          },
          (value) => {
            const row = recordOf(value, "update_employees");
            return {
              accepted: recordsOf(row["accepted"], "accepted").map((item) => ({
                employeeId: textOf(item["employeeId"]),
                field: textOf(item["field"]),
              })),
              rejected: recordsOf(row["rejected"], "rejected").map((item) =>
                compact<EmployeeChangeResult["rejected"][number]>({
                  employeeId: textOf(item["employeeId"]),
                  field: textOf(item["field"]),
                  hint: optionalText(item["hint"]),
                  reason: textOf(item["reason"]),
                }),
              ),
            };
          },
        ),
      ),
    offboard: (employeeId, offboard = {}) =>
      call(
        "offboard_employee",
        {
          employee: employeeId,
          end_date: offboard.endDate?.toString() ?? null,
          reason: offboard.reason ?? null,
        },
        employeeOf,
      ).andThen(parsed),
    orgChart: (organizationId, rootId) =>
      chart("org_chart", { tenant: organizationId, root: rootId ?? null }),
    reportsOf: (managerId, reports = {}) =>
      chart("reports_of", {
        manager: managerId,
        indirect: reports.indirect ?? false,
      }),
    fromApplication: (applicationId, overrides = {}) =>
      attrsOf(overrides)
        .andThen((attrs) =>
          call(
            "employee_from_application",
            { application: applicationId, attrs },
            employeeOf,
          ),
        )
        .andThen(parsed),
    privateDetails: (employeeId) =>
      call("employee_private_details", { employee: employeeId }, (value) =>
        value === null || value === undefined ? undefined : privateOf(value),
      ),
    savePrivateDetails: (employeeId, input) =>
      call(
        "save_employee_private_details",
        {
          employee: employeeId,
          attrs: argsOf({
            ...input,
            ...(input.emergencyContacts
              ? {
                  emergencyContacts: input.emergencyContacts.map((contact) => ({
                    ...contact,
                  })),
                }
              : {}),
          }),
        },
        privateOf,
      ),
    contracts: (employeeId) =>
      call("employee_contracts", { employee: employeeId }, (value) =>
        recordsOf(value, "employee_contracts").map(contractOf),
      ),
    addContract: (employeeId, input) =>
      call(
        "add_employee_contract",
        { employee: employeeId, attrs: argsOf(input) },
        contractOf,
      ),
  };
  return withBlockHooks(client, options.hooks, {
    block: "employees",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}

/**
 * The `config.subjects` entry for employees, so comments, files, tags and
 * search attach to them. Pass `schema` when the module isn't in
 * `better_supabase`.
 */
export function employeesSubjects(
  options: { readonly schema?: string; readonly url?: string } = {},
): { readonly employee: SubjectConfig } {
  return {
    employee: {
      table: `${options.schema ?? DEFAULT_BLOCK_SCHEMA}.employees`,
      idType: "uuid",
      tenant: "tenant_id",
      title: "name",
      permissions: { read: "employees.read", write: "employees.write" },
      search: { title: "name", body: ["email", "job_title"] },
      ...(options.url === undefined ? {} : { url: options.url }),
    },
  };
}
