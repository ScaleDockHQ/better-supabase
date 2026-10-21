import "server-only";
import type { EmployeeStatus } from "better-supabase/blocks/employees";
import type { TimesheetStatus } from "better-supabase/blocks/time-tracking";

import { toWeeklyGrid } from "better-supabase/blocks/time-tracking";
import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import { blocks } from "@/lib/blocks";
import { blockConfig } from "@/lib/supabase/blocks.generated";
import { bs } from "@/lib/supabase/server";

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

/** The zone the time-tracking block starts its days in. */
export const TIME_ZONE = blockConfig["time-tracking"].options.timeZone;

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

/**
 * Every employee who isn't offboarded, ordered as the org chart: each manager
 * before their reports, with the depth below the top.
 */
export async function loadDirectory(): Promise<
  readonly DirectoryEmployee[] | null
> {
  "use cache: private";
  const { session, supabase } = await bs.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const chart = await blocks(supabase).employees.orgChart(tenant).orThrow();

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
  const { session, supabase } = await bs.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const { timeTracking } = blocks(supabase, tenant);

  const [sheet, running] = await Promise.all([
    timeTracking.timesheet(Temporal.PlainDate.from(week)).orThrow(),
    timeTracking.running().orThrow(),
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

const Id = v.pipe(v.string(), v.uuid());

const JobRow = v.object({
  id: Id,
  title: v.string(),
  status: v.picklist(["draft", "open", "closed"]),
  location: v.nullish(v.string()),
});

const ApplicationRow = v.object({
  id: Id,
  job_id: Id,
  stage_id: v.nullish(Id),
  state: v.string(),
  candidate_type: v.string(),
  candidate_id: v.string(),
  candidate_name: v.nullish(v.string()),
});

const StageRow = v.object({
  id: Id,
  name: v.string(),
  category: v.string(),
  archived_at: v.nullish(v.string()),
});

const PipelineRow = v.object({ id: Id, stages: v.array(StageRow) });

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
 * them. The hiring block has no list function yet, so this reads
 * `api.list_jobs` and `api.list_applications`; until they exist the read fails
 * and the board shows Retry. Candidates are customers, the one subject type the
 * app registers.
 */
export async function loadHiringBoard(): Promise<HiringBoardData | null> {
  "use cache: private";
  const { session, supabase, db } = await bs.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const { call } = blocks(supabase);

  const [jobs, applications, pipelines, customers] = await Promise.all([
    call("list_jobs", { tenant }),
    call("list_applications", { tenant }),
    call("list_pipelines", { tenant, subject_type: "application" }),
    db.customers
      .findMany({
        select: ["id", "name"],
        orderBy: { name: "asc" },
        limit: 200,
      })
      .orThrow(),
  ]);

  const pipeline = v.parse(v.array(PipelineRow), pipelines)[0];

  return {
    jobs: v
      .parse(v.array(JobRow), jobs)
      .map((job) => ({
        id: job.id,
        title: job.title,
        status: job.status,
        location: job.location ?? null,
      })),
    stages: (pipeline?.stages ?? [])
      .filter((stage) => !stage.archived_at)
      .map((stage) => ({
        id: stage.id,
        name: stage.name,
        category: stage.category,
      })),
    cards: v
      .parse(v.array(ApplicationRow), applications)
      .flatMap((application) =>
        application.stage_id
          ? [
              {
                id: application.id,
                jobId: application.job_id,
                stageId: application.stage_id,
                name: application.candidate_name ?? application.candidate_id,
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
