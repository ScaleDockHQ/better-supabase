import "server-only";
import type { Money } from "better-supabase/commerce";

import { money } from "better-supabase/commerce";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";
import { Temporal } from "temporal-polyfill";

import { projectsOf } from "@/features/composites/composites";
import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

const PORTFOLIO_LIMIT = 50;
const SECONDS_PER_HOUR = 3600;

/** What a project's tracked time is worth against its budget. */
export interface ProjectFinance {
  readonly hours: number;
  readonly billableHours: number;
  readonly entries: number;
  readonly billable: readonly Money[];
  readonly budget: Money;
  readonly remaining: Money | null;
  readonly exhausted: boolean;
}

/** One row of the portfolio: a project with its tracked hours. */
export interface PortfolioRow {
  readonly id: string;
  readonly name: string;
  readonly budget: Money;
  readonly hours: number;
  readonly billableHours: number;
}

/** A submitted week that waits for a decision and an invoice. */
export interface AwaitingTimesheet {
  readonly id: string;
  readonly userId: string;
  readonly week: string;
}

export interface Portfolio {
  readonly rows: readonly PortfolioRow[];
  readonly awaiting: readonly AwaitingTimesheet[];
  readonly utilization: number;
  readonly weekHours: number;
}

/**
 * The time tracked on a project and how much of its budget the billable time
 * used: `projects.financials` and `projects.retainerDrawdown`, the budget as
 * the retainer. `undefined` when the project does not exist.
 */
export async function getProjectFinance(
  id: string,
): Promise<ProjectFinance | undefined | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(tags.projects(), tags.work());

  if (!tenantOf(session)) {
    return null;
  }

  const project = await db.projects
    .get(
      { where: { id: { eq: id }, deletedAt: { isNull: true } } },
      { select: ["id", "budgetMinor", "currency"], optional: true },
    )
    .orThrow();

  if (!project) {
    return undefined;
  }

  const projects = projectsOf(db);
  const budget = money(project.budgetMinor, project.currency);
  const financials = await projects.financials({ projectId: id }).orThrow();

  const drawdown =
    project.budgetMinor > 0n
      ? await projects
          .retainerDrawdown({ projectId: id, retainer: budget })
          .orThrow()
      : null;

  return {
    hours: financials.seconds / SECONDS_PER_HOUR,
    billableHours: financials.billableSeconds / SECONDS_PER_HOUR,
    entries: financials.entries,
    billable: financials.billable,
    budget,
    remaining: drawdown?.remaining ?? null,
    exhausted: drawdown?.exhausted ?? false,
  };
}

/**
 * Every project with its tracked hours, and the team's utilization this week:
 * `projects.financials` per project and `projects.utilization`.
 */
export async function getPortfolio(): Promise<Portfolio | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  cacheTag(tags.projects(), tags.work());
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const projects = projectsOf(db);

  const [list, week, submitted] = await Promise.all([
    db.projects
      .list({
        select: ["id", "name", "budgetMinor", "currency"],
        where: { organizationId: { eq: tenant }, deletedAt: { isNull: true } },
        orderBy: { name: "asc" },
        limit: PORTFOLIO_LIMIT,
      })
      .orThrow(),
    projects
      .utilization({ weekOf: Temporal.Now.plainDateISO("UTC") })
      .orThrow(),
    db.timeEntries.timesheets({ status: "submitted", pageSize: 10 }).orThrow(),
  ]);

  const rows = await Promise.all(
    list.map(async (project): Promise<PortfolioRow> => {
      const financials = await projects
        .financials({ projectId: project.id })
        .orThrow();

      return {
        id: project.id,
        name: project.name,
        budget: money(project.budgetMinor, project.currency),
        hours: financials.seconds / SECONDS_PER_HOUR,
        billableHours: financials.billableSeconds / SECONDS_PER_HOUR,
      };
    }),
  );

  const seconds = week.members.reduce((sum, member) => sum + member.seconds, 0);

  const capacity = week.capacityHours * Math.max(week.members.length, 1);

  const awaiting = submitted.flatMap((sheet) =>
    sheet.id === undefined
      ? []
      : [{ id: sheet.id, userId: sheet.userId, week: sheet.week.toString() }],
  );

  return {
    rows,
    awaiting,
    weekHours: seconds / SECONDS_PER_HOUR,
    utilization: capacity === 0 ? 0 : seconds / SECONDS_PER_HOUR / capacity,
  };
}
