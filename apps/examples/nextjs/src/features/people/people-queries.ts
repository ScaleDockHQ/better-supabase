import "server-only";
import type { EmployeeStatus } from "better-supabase/blocks/employees";
import type { TimesheetStatus } from "better-supabase/blocks/time-entries";

import { toWeeklyGrid } from "better-supabase/blocks/time-entries";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";
import { unstable_rethrow } from "next/navigation";
import { Temporal } from "temporal-polyfill";

import { CUSTOMERS_TAG } from "@/features/customers/customers-cache";
import { blockConfig } from "@/lib/supabase/blocks.config";
import { bsb } from "@/lib/supabase/server";

import { PEOPLE_TAG } from "./people-cache";

/** What a loader gives a component: the data, a failed read, or no organization. */
export type Loaded<T> =
  | { readonly kind: "ok"; readonly data: T }
  | { readonly kind: "error" }
  | { readonly kind: "no-organization" };

/**
 * Runs a loader and turns a thrown read into `{ kind: "error" }`, so the
 * component shows Retry. A failed read is never cached.
 */
export async function settle<T>(
  load: () => Promise<T | null>,
): Promise<Loaded<T>> {
  try {
    const data = await load();

    return data === null ? { kind: "no-organization" } : { kind: "ok", data };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}

/** The zone the time-entries block starts its days in. */
export const TIME_ZONE = blockConfig["time-entries"].options.timeZone;

export interface DirectoryEmployee {
  readonly id: string;
  readonly name: string;
  readonly email: string | null;
  readonly jobTitle: string | null;
  readonly managerId: string | null;
  readonly status: EmployeeStatus;
  readonly startDate: string | null;
  readonly depth: number;
  readonly directReports: number;
}

type Db = Awaited<ReturnType<typeof bsb.cached>>["db"];

/**
 * Every employee who isn't offboarded, ordered as the org chart: each manager
 * before their reports, with the depth below the top. The list route calls it
 * with its own `db`; the page reads it through `loadDirectory`.
 */
export async function readDirectory(
  db: Db,
  tenant: string,
): Promise<readonly DirectoryEmployee[]> {
  const chart = await db.employees
    .orgChart({ organizationId: tenant })
    .orThrow();

  return chart.map((employee) => ({
    id: employee.id,
    name: employee.name,
    email: employee.email ?? null,
    jobTitle: employee.jobTitle ?? null,
    managerId: employee.managerId ?? null,
    status: employee.status,
    startDate: employee.startDate?.toString() ?? null,
    depth: employee.depth,
    directReports: employee.directReports,
  }));
}

export async function loadDirectory(): Promise<
  readonly DirectoryEmployee[] | null
> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(PEOPLE_TAG, CUSTOMERS_TAG);
  const tenant = tenantOf(session);

  return tenant ? readDirectory(db, tenant) : null;
}

export interface EmployeeDetail {
  readonly employee: DirectoryEmployee;
  readonly managerName: string | null;
  readonly reports: readonly Pick<
    DirectoryEmployee,
    "id" | "name" | "jobTitle"
  >[];
  readonly contracts: readonly {
    readonly id: string;
    readonly hoursPerWeek: number | null;
    readonly startsOn: string;
    readonly endsOn: string | null;
  }[];
}

/** One employee with their manager, direct reports and contracts. */
export async function loadEmployee(
  id: string,
): Promise<EmployeeDetail | "not-found" | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(PEOPLE_TAG, CUSTOMERS_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const directory = await readDirectory(db, tenant);
  const employee = directory.find((entry) => entry.id === id);

  if (!employee) {
    return "not-found";
  }

  const contracts = await db.employees.contracts(id);

  return {
    employee,
    managerName:
      directory.find((entry) => entry.id === employee.managerId)?.name ?? null,
    reports: directory
      .filter((entry) => entry.managerId === id)
      .map(({ id: reportId, name, jobTitle }) => ({
        id: reportId,
        name,
        jobTitle,
      })),
    contracts: contracts.ok
      ? contracts.data.map((contract) => ({
          id: contract.id,
          hoursPerWeek: contract.hoursPerWeek ?? null,
          startsOn: contract.startsOn.toString(),
          endsOn: contract.endsOn?.toString() ?? null,
        }))
      : [],
  };
}

export interface WeekCell {
  readonly date: string;
  readonly seconds: number;
}

export interface TimesheetRow {
  readonly id: string;
  readonly label: string;
  readonly billable: boolean;
  readonly days: readonly number[];
  readonly seconds: number;
}

export interface TimesheetWeek {
  readonly week: string;
  readonly status: TimesheetStatus;
  readonly days: readonly WeekCell[];
  readonly rows: readonly TimesheetRow[];
  readonly seconds: number;
  readonly billableSeconds: number;
  readonly running: {
    readonly note: string | null;
    readonly startedAt: string;
  } | null;
}

/**
 * The caller's week starting on the Monday of `week`: one row per project (the
 * entry's note) and whether it bills, and the running timer.
 */
export async function loadTimesheet(
  week: string,
): Promise<TimesheetWeek | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(PEOPLE_TAG, CUSTOMERS_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const { timeEntries } = db;

  const [sheet, running] = await Promise.all([
    timeEntries.timesheet({ week: Temporal.PlainDate.from(week) }).orThrow(),
    timeEntries.running().orThrow(),
  ]);

  const labels = new Map(
    sheet.entries.map((entry) => [entry.id, entry.note ?? ""]),
  );

  const grid = toWeeklyGrid(sheet.entries, {
    week: sheet.week,
    timeZone: TIME_ZONE,
    rowKey: (entry) => `${entry.note ?? ""}:${String(entry.billable)}`,
  });

  return {
    week: sheet.week.toString(),
    status: sheet.status,
    days: grid.days.map((day) => ({ date: day.id, seconds: day.seconds })),
    rows: grid.rows.map((row) => ({
      id: row.id,
      label: labels.get(row.entryIds[0] ?? "") ?? "",
      billable: row.billable,
      days: row.days,
      seconds: row.seconds,
    })),
    seconds: grid.seconds,
    billableSeconds: grid.billableSeconds,
    running: running
      ? { note: running.note ?? null, startedAt: running.startedAt.toString() }
      : null,
  };
}

export interface HiringJob {
  readonly id: string;
  readonly title: string;
  readonly status: "draft" | "open" | "closed";
  readonly location: string | null;
}

export interface HiringStage {
  readonly id: string;
  readonly name: string;
  readonly category: string;
}

export interface HiringCard {
  readonly id: string;
  readonly jobId: string;
  readonly stageId: string;
  readonly name: string;
}

export interface CandidateOption {
  readonly value: string;
  readonly label: string;
}

export interface HiringBoardData {
  readonly jobs: readonly HiringJob[];
  readonly stages: readonly HiringStage[];
  readonly cards: readonly HiringCard[];
  readonly candidates: readonly CandidateOption[];
}

/**
 * The openings, the stages of the application pipeline and the candidates in
 * them. Candidates are customers, the one subject type the app registers.
 */
export async function loadHiringBoard(): Promise<HiringBoardData | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(PEOPLE_TAG, CUSTOMERS_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const [jobs, pipeline, customers] = await Promise.all([
    db.hiring.jobs({ organizationId: tenant }).orThrow(),
    db.pipelines
      .default({ organizationId: tenant, subjectType: "application" })
      .orThrow(),
    db.customers
      .list({ select: ["id", "name"], orderBy: { name: "asc" }, limit: 200 })
      .orThrow(),
  ]);

  const applications = await db.hiring
    .applicationsForJobs({ jobIds: jobs.map((job) => job.id) })
    .orThrow();

  const names = new Map(
    customers.map((customer) => [customer.id, customer.name]),
  );

  return {
    jobs: jobs.map((job) => ({
      id: job.id,
      title: job.title,
      status: job.status,
      location: job.location ?? null,
    })),
    stages: (pipeline?.stages ?? []).map((stage) => ({
      id: stage.id,
      name: stage.name,
      category: stage.category,
    })),
    cards: applications.flatMap((application) =>
      application.stageId
        ? [
            {
              id: application.id,
              jobId: application.jobId,
              stageId: application.stageId,
              name:
                names.get(application.candidate.id) ?? application.candidate.id,
            },
          ]
        : [],
    ),
    candidates: customers.map((customer) => ({
      value: customer.id,
      label: customer.name,
    })),
  };
}
