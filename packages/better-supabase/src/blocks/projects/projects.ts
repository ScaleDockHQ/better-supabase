import type { Money } from "../../commerce/money.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type {
  InvoiceFromTimeInput,
  TimeInvoice,
} from "../billable-time/index.ts";
import type { BlockContext } from "../create-blocks.ts";
import type { CompositeOptions } from "../define-block.ts";
import type { Timesheet } from "../time-entries/index.ts";
import type { ProjectsParts } from "./manifest.ts";
import type { ProjectCard, ProjectOverview } from "./overview.ts";

import { money, roundHalfEven } from "../../commerce/money.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult as Async, ok } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import { projectPage } from "./page.ts";

/** What `projects.approveAndInvoice` returns. */
export interface ApprovedAndInvoiced {
  readonly timesheet: Timesheet;
  readonly invoice: TimeInvoice;
}

/** One member's hours in a week. */
export interface MemberUtilization {
  readonly userId: string;
  readonly seconds: number;
  readonly billableSeconds: number;
  /** Tracked hours over the capacity: 1 is fully booked. */
  readonly utilization: number;
  /** Billable hours over the capacity. */
  readonly billableUtilization: number;
}

/** What `projects.utilization` returns. */
export interface Utilization {
  readonly weekStart: Temporal.PlainDate;
  readonly capacityHours: number;
  readonly members: readonly MemberUtilization[];
}

/** What `projects.financials` returns. */
export interface ProjectFinancials {
  readonly entries: number;
  readonly seconds: number;
  readonly billableSeconds: number;
  /** The billable value of the finished entries with a rate, per currency. */
  readonly billable: readonly Money[];
}

/** What `projects.retainerDrawdown` returns. */
export interface RetainerDrawdown {
  readonly retainer: Money;
  /** The billable value drawn, in the retainer's currency. */
  readonly drawn: Money;
  /** The retainer left, never below zero. */
  readonly remaining: Money;
  readonly exhausted: boolean;
}

/** The helpers `projects` adds over its parts. */
export interface Projects {
  /**
   * Approves the timesheet (`timeEntries.approve`), then invoices the time
   * `invoice` selects (`billableTime.invoice`). A refused approval invoices
   * nothing. A failed invoice returns its error and leaves the timesheet
   * approved, so retry it with `billableTime.invoice`.
   */
  approveAndInvoice(input: {
    timesheetId: string;
    decidedBy?: string | undefined;
    invoice?: InvoiceFromTimeInput | undefined;
  }): AsyncResult<ApprovedAndInvoiced>;
  /**
   * The hours every member tracked in the ISO week that holds `weekOf`
   * (`timeEntries.list` for everyone), against `capacityHours` (40 by default).
   * An entry that crosses the week's edge counts only the part inside it. Needs
   * `time_entries.read`.
   */
  utilization(input: {
    weekOf: Temporal.PlainDate;
    capacityHours?: number | undefined;
    /** The zone the week starts in. Default: `UTC`. */
    timeZone?: string | undefined;
  }): AsyncResult<Utilization>;
  /**
   * The time tracked on a project and its billable value: hours times each
   * entry's rate, rounded half to even per entry. Running entries are not
   * counted. Needs `time_entries.read`.
   */
  financials(input: { projectId: string }): AsyncResult<ProjectFinancials>;
  /**
   * How much of a prepaid `retainer` the project's billable time has used.
   * Entries in another currency than the retainer's are not counted.
   */
  retainerDrawdown(input: {
    projectId: string;
    retainer: Money;
  }): AsyncResult<RetainerDrawdown>;
  /**
   * The project page: the project, its record team, task counts per state,
   * financials, blocking projects, file count, recent activity and the views
   * saved under `project:<id>`. The first failed read is the result.
   */
  overview(input: {
    organizationId: string;
    projectId: string;
    /** The project subject's type. Default: `project`. */
    subjectType?: string;
  }): AsyncResult<ProjectOverview>;
  /**
   * Comment counts, tags, file counts and sub-task progress for each task, in
   * one round of reads.
   */
  cards(input: {
    organizationId: string;
    taskIds: readonly string[];
    /** The task subject's type. Default: `task`. */
    subjectType?: string;
  }): AsyncResult<Readonly<Record<string, ProjectCard>>>;
  /** The views saved for one project, under the list key `project:<id>`. */
  views(
    projectId: string,
  ): AsyncResult<readonly { readonly id: string; readonly name: string }[]>;
  /** Posts an update, sets the project's health and tells its subscribers. */
  postUpdate(input: {
    organizationId: string;
    projectId: string;
    health: "on_track" | "at_risk" | "off_track";
    body: string;
  }): AsyncResult<Readonly<Record<string, unknown>>>;
  /**
   * Projects this one blocks and projects that block it. `violated` is true
   * when the blocker's target date is after the dependent's start date.
   */
  dependencies(input: {
    projectId: string;
    subjectType?: string;
  }): AsyncResult<
    readonly {
      readonly direction: "in" | "out";
      readonly projectId: string;
      readonly violated: boolean;
    }[]
  >;
  saveInitiative(input: {
    organizationId: string;
    initiativeId?: string;
    name: string;
    description?: string;
    status?: string;
    priority?: number;
    ownerId?: string;
    targetOn?: string;
    parentId?: string;
  }): AsyncResult<Readonly<Record<string, unknown>>>;
  pageInitiatives(
    organizationId: string,
  ): AsyncResult<readonly Record<string, unknown>[]>;
  linkInitiative(input: {
    initiativeId: string;
    projectId: string;
  }): AsyncResult<boolean>;
}

const HOUR_SECONDS = 3600n;

/** The value of `seconds` at an hourly `rate`. */
const valueOf = (rate: Money, seconds: number): Money =>
  money(
    roundHalfEven(rate.amount * BigInt(seconds), HOUR_SECONDS),
    rate.currency,
  );

/** What the `projects` creator receives. */
export type ProjectsOptions = BlockContext &
  CompositeOptions<ProjectsParts> & {
    /** `before` and `after` hooks per method (ADR 0015). */
    readonly hooks?: NoInfer<BlockHooks<Projects>>;
    /** Receives the errors `after` hooks throw. Default: `console`. */
    readonly logger?: Logger;
  };

/** Sums finished entries into hours and the billable value per currency. */
function billableOf(
  entries: readonly {
    readonly seconds?: number;
    readonly billable: boolean;
    readonly rate?: Money;
  }[],
): ProjectFinancials {
  const values = new Map<string, bigint>();
  let seconds = 0;
  let billableSeconds = 0;
  let counted = 0;

  for (const entry of entries) {
    if (entry.seconds === undefined) {
      continue;
    }

    counted += 1;
    seconds += entry.seconds;

    if (!entry.billable) {
      continue;
    }

    billableSeconds += entry.seconds;

    if (entry.rate !== undefined) {
      const value = valueOf(entry.rate, entry.seconds);

      values.set(
        value.currency,
        (values.get(value.currency) ?? 0n) + value.amount,
      );
    }
  }

  return {
    entries: counted,
    seconds,
    billableSeconds,
    billable: [...values].map(([currency, amount]) => money(amount, currency)),
  };
}

/** Creates the `projects` helpers over the clients of its parts. */
export function createProjects(options: ProjectsOptions): Projects {
  const { "time-entries": timeEntries, "billable-time": billableTime } =
    options.parts;

  const financialsOf = (input: {
    projectId: string;
    subjectType?: string;
  }): AsyncResult<ProjectFinancials> =>
    timeEntries
      // oxlint-disable-next-line typescript/no-deprecated -- the deprecated method stays an alias until 0.70 (ADR 1077)
      .list({
        everyone: true,
        subject: { type: input.subjectType ?? "project", id: input.projectId },
      })
      .map(billableOf);

  const financials = (input: {
    projectId: string;
  }): AsyncResult<ProjectFinancials> => financialsOf(input);

  const page = projectPage(options, financialsOf);

  const client: Projects = {
    approveAndInvoice: ({ timesheetId, decidedBy, invoice }) =>
      Async.from(async () => {
        const timesheet = await timeEntries.approve({
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
    utilization: ({ weekOf, capacityHours = 40, timeZone = "UTC" }) =>
      Async.from(async () => {
        const T = temporal();
        const weekStart = weekOf.subtract({ days: weekOf.dayOfWeek - 1 });
        const from = weekStart.toZonedDateTime(timeZone).toInstant();

        const to = weekStart
          .add({ days: 7 })
          .toZonedDateTime(timeZone)
          .toInstant();

        // oxlint-disable-next-line typescript/no-deprecated -- the deprecated method stays an alias until 0.70 (ADR 1077)
        const entries = await timeEntries.list({ everyone: true, from, to });

        if (!entries.ok) {
          return entries;
        }

        const byUser = new Map<string, { all: number; billable: number }>();

        for (const entry of entries.data) {
          if (entry.endedAt === undefined) {
            continue;
          }

          const start =
            T.Instant.compare(entry.startedAt, from) < 0
              ? from
              : entry.startedAt;

          const end =
            T.Instant.compare(entry.endedAt, to) > 0 ? to : entry.endedAt;

          const seconds = Math.max(
            0,
            Math.round(
              end.epochMilliseconds / 1000 - start.epochMilliseconds / 1000,
            ),
          );

          const sum = byUser.get(entry.userId) ?? { all: 0, billable: 0 };

          byUser.set(entry.userId, {
            all: sum.all + seconds,
            billable: sum.billable + (entry.billable ? seconds : 0),
          });
        }

        const capacity = capacityHours * 3600;

        return ok({
          weekStart,
          capacityHours,
          members: [...byUser].map(([userId, sum]) => ({
            userId,
            seconds: sum.all,
            billableSeconds: sum.billable,
            utilization: capacity === 0 ? 0 : sum.all / capacity,
            billableUtilization: capacity === 0 ? 0 : sum.billable / capacity,
          })),
        });
      }),
    financials,
    retainerDrawdown: ({ projectId, retainer }) =>
      timeEntries
        // oxlint-disable-next-line typescript/no-deprecated -- the deprecated method stays an alias until 0.70 (ADR 1077)
        .list({ everyone: true, subject: { type: "project", id: projectId } })
        .map((entries) => {
          const billable = billableOf(entries).billable.find(
            (value) => value.currency === retainer.currency,
          );

          const drawn = billable ?? money(0n, retainer.currency);
          const left = retainer.amount - drawn.amount;

          return {
            retainer,
            drawn,
            remaining: money(left < 0n ? 0n : left, retainer.currency),
            exhausted: left <= 0n,
          };
        }),
    overview: page.overview,
    cards: page.cards,
    views: page.views,
    postUpdate: page.postUpdate,
    dependencies: page.dependencies,
    saveInitiative: page.saveInitiative,
    pageInitiatives: page.pageInitiatives,
    linkInitiative: page.linkInitiative,
  };

  return withBlockHooks(client, options.hooks, {
    block: "projects",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
