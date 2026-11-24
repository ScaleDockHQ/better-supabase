import "server-only";
import type { EmployeeStatus } from "better-supabase/blocks/employees";
import type { TimesheetStatus } from "better-supabase/blocks/time-entries";

import { toWeeklyGrid } from "better-supabase/blocks/time-entries";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";
import { unstable_rethrow } from "next/navigation";
import { Temporal } from "temporal-polyfill";

import type {
  RecordListPage,
  RecordListUrlQuery,
} from "@/components/record-list/record-list-types";

import { CUSTOMERS_TAG } from "@/features/customers/customers-cache";
import { pageEntityRows } from "@/lib/block-entity-page";
import { blockConfig } from "@/lib/supabase/blocks.config";
import { bsb } from "@/lib/supabase/server";

import type { EmployeeRow } from "./employees-list";

import { employeeList, employeeMap } from "./employees-list";
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

/** One page of the directory for a list query, with its facet counts. */
export function loadEmployeePage(
  db: Db,
  organizationId: string,
  query: RecordListUrlQuery,
): Promise<RecordListPage<EmployeeRow>> {
  const { employees } = db;

  return pageEntityRows({
    pager: {
      page: (options) => employees.page({ organizationId, ...options }),
      facets: (options) => employees.facets({ organizationId, ...options }),
    },
    map: employeeMap,
    query,
    pageSize: employeeList.config.pageSize,
    rowsOf: (items) =>
      items.map((employee): EmployeeRow => ({
        id: employee.id,
        name: employee.name,
        email: employee.email ?? null,
        jobTitle: employee.jobTitle ?? null,
        status: employee.status,
        startDate: employee.startDate?.toString() ?? null,
      })),
  });
}

export interface DirectoryData {
  readonly initial: RecordListPage<EmployeeRow>;
  /** Who a new employee can report to. */
  readonly managers: readonly {
    readonly value: string;
    readonly label: string;
  }[];
}

export async function loadDirectory(): Promise<DirectoryData | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(PEOPLE_TAG, CUSTOMERS_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const [initial, directory] = await Promise.all([
    loadEmployeePage(db, tenant, employeeList.defaults),
    readDirectory(db, tenant),
  ]);

  return {
    initial,
    managers: directory.map((employee) => ({
      value: employee.id,
      label: employee.name,
    })),
  };
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

export type ApplicationState = "active" | "hired" | "rejected" | "withdrawn";

export interface ApplicationRow {
  readonly id: string;
  readonly jobId: string;
  readonly jobTitle: string;
  readonly candidateId: string;
  readonly candidateName: string;
  readonly stageId: string | null;
  readonly stageName: string | null;
  readonly state: ApplicationState;
  readonly source: string | null;
  readonly createdAt: string;
}

export interface ApplicationsData {
  readonly rows: readonly ApplicationRow[];
  readonly stages: readonly HiringStage[];
}

/**
 * Every application of every opening, with the opening, stage and candidate
 * named.
 */
export async function loadApplications(): Promise<ApplicationsData | null> {
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

  const jobTitles = new Map(jobs.map((job) => [job.id, job.title]));
  const stages = pipeline?.stages ?? [];
  const stageNames = new Map(stages.map((stage) => [stage.id, stage.name]));

  return {
    stages: stages.map((stage) => ({
      id: stage.id,
      name: stage.name,
      category: stage.category,
    })),
    rows: applications.map((application) => ({
      id: application.id,
      jobId: application.jobId,
      jobTitle: jobTitles.get(application.jobId) ?? "",
      candidateId: application.candidate.id,
      candidateName:
        names.get(application.candidate.id) ?? application.candidate.id,
      stageId: application.stageId ?? null,
      stageName:
        application.stageId === undefined
          ? null
          : (stageNames.get(application.stageId) ?? null),
      state: application.state,
      source: application.source ?? null,
      createdAt: application.createdAt.toString(),
    })),
  };
}

export interface ApplicationView {
  readonly row: ApplicationRow;
  readonly stages: readonly HiringStage[];
  readonly rejectionReason: string | null;
  readonly hiredAt: string | null;
  readonly scorecards: readonly {
    readonly id: string;
    readonly rating: number;
    readonly recommendation: string | null;
    readonly notes: string | null;
    readonly submittedAt: string;
  }[];
  readonly interviews: readonly {
    readonly id: string;
    readonly kind: string | null;
    readonly startsAt: string;
    readonly location: string | null;
  }[];
}

/** One application with its stage path, scorecards and interviews. */
export async function loadApplication(
  id: string,
): Promise<ApplicationView | "not-found" | null> {
  "use cache: private";
  const { db } = await bsb.cached();
  cacheTag(PEOPLE_TAG, CUSTOMERS_TAG);

  const all = await loadApplications();

  if (all === null) {
    return null;
  }

  const row = all.rows.find((entry) => entry.id === id);

  if (!row) {
    return "not-found";
  }

  const detail = await db.hiring.detail(id);

  if (!detail.ok) {
    return {
      row,
      stages: all.stages,
      rejectionReason: null,
      hiredAt: null,
      scorecards: [],
      interviews: [],
    };
  }

  const jobPipeline =
    all.stages.length === 0 && detail.data.pipelineId !== undefined
      ? await db.pipelines.get(detail.data.pipelineId)
      : null;

  const stages = jobPipeline?.ok
    ? jobPipeline.data.stages.map((stage) => ({
        id: stage.id,
        name: stage.name,
        category: stage.category,
      }))
    : all.stages;

  return {
    row,
    stages,
    rejectionReason: detail.data.rejectionReason ?? null,
    hiredAt: detail.data.hiredAt?.toString() ?? null,
    scorecards: detail.data.scorecards.map((card) => ({
      id: card.id,
      rating: card.rating,
      recommendation: card.recommendation ?? null,
      notes: card.notes ?? null,
      submittedAt: card.submittedAt.toString(),
    })),
    interviews: detail.data.interviews.map((interview) => ({
      id: interview.id,
      kind: interview.kind ?? null,
      startsAt: interview.startsAt.toString(),
      location: interview.location ?? null,
    })),
  };
}

/**
 * Everyone in the directory, with status and manager, for the board and
 * figures.
 */
export async function loadRoster(): Promise<
  readonly DirectoryEmployee[] | null
> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(PEOPLE_TAG, CUSTOMERS_TAG);
  const tenant = tenantOf(session);

  return tenant ? readDirectory(db, tenant) : null;
}
