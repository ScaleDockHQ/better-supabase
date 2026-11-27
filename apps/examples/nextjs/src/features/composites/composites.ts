import "server-only";
import type { Tasks } from "better-supabase/blocks/tasks";

import { rpcTransport } from "better-supabase/blocks";
import { createCare } from "better-supabase/blocks/care";
import { createCommerce } from "better-supabase/blocks/commerce";
import { createCrm } from "better-supabase/blocks/crm";
import { createFilespace } from "better-supabase/blocks/filespace";
import { createFinance } from "better-supabase/blocks/finance";
import { createGovernance } from "better-supabase/blocks/governance";
import { createLearning } from "better-supabase/blocks/learning";
import { createPeople } from "better-supabase/blocks/people";
import { createProcurement } from "better-supabase/blocks/procurement";
import { createProjects } from "better-supabase/blocks/projects";
import { createRecruiting } from "better-supabase/blocks/recruiting";
import { createKeyRotator } from "better-supabase/blocks/saas";
import { createSales } from "better-supabase/blocks/sales";
import { createScheduling } from "better-supabase/blocks/scheduling";
import { createSupport } from "better-supabase/blocks/support";

import type { driveOf } from "@/features/drive/drive-client";
import type { AppDb } from "@/lib/supabase";

/**
 * The `crm` composite's helpers over the clients this app already installs. The
 * parts stay ordinary blocks in the config; the composite adds `closeWon` and
 * `closeLost` on top of them.
 */
export function crmOf(db: AppDb) {
  const { $blocks: blocks } = db;

  return createCrm({
    transport: rpcTransport(db.$client),
    parts: {
      contacts: blocks.contacts,
      pipelines: blocks.pipelines,
      deals: blocks.deals,
      quotes: blocks.quotes,
      goals: blocks.goals,
      activities: blocks.activities,
      "mail-sync": blocks.mailSync,
      sequences: blocks.sequences,
      segments: blocks.segments,
      assignment: blocks.assignment,
      enrichment: blocks.enrichment,
      forecasts: blocks.forecasts,
      "lead-scoring": blocks.leadScoring,
      queue: blocks.queue,
    },
  });
}

/**
 * The `filespace` composite's helpers over the drive, attachments, versions,
 * share-links, search and trash clients: `put`, `bulkShare` and `publicLink`.
 */
export function filespaceOf(db: AppDb, drive: ReturnType<typeof driveOf>) {
  const { $blocks: blocks } = db;

  return createFilespace({
    transport: rpcTransport(db.$client),
    parts: {
      drive,
      attachments: blocks.attachments,
      versions: blocks.versions,
      "share-links": blocks.shareLinks,
      search: blocks.search,
      trash: blocks.trash,
    },
  });
}

/**
 * The composites call the tasks block under its default names, and this app
 * names the entity `work_item`: `assign` takes the id as `workItemId`.
 */
function defaultTasks(tasks: AppDb["$blocks"]["tasks"]): Tasks {
  // SAFETY: the composites call `create` and `assign` only; `assign` is
  // translated, and every other method keeps its renamed input.
  // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- the renamed client's other inputs differ from the default `Tasks` (1 finding)
  return {
    ...tasks,
    assign: (input: { taskId: string; userIds: readonly string[] }) =>
      tasks.assign({ workItemId: input.taskId, userIds: input.userIds }),
  } as unknown as Tasks;
}

/**
 * The `support` composite's helpers: `openTicket` and `escalate` over the
 * inbox, tasks, SLA and knowledge clients.
 */
export function supportOf(db: AppDb) {
  const { $blocks: blocks } = db;

  return createSupport({
    transport: rpcTransport(db.$client),
    parts: {
      inbox: blocks.inbox,
      tasks: defaultTasks(blocks.tasks),
      sla: blocks.sla,
      knowledge: blocks.knowledge,
    },
  });
}

/**
 * The `commerce` composite's helpers: `payAndFulfil` and `processReturn` over
 * the catalog, inventory, orders and promotions clients.
 */
export function commerceOf(db: AppDb) {
  const { $blocks: blocks } = db;

  return createCommerce({
    transport: rpcTransport(db.$client),
    parts: {
      catalog: blocks.catalog,
      inventory: blocks.inventory,
      orders: blocks.orders,
      promotions: blocks.promotions,
    },
  });
}

/**
 * The `projects` composite's helpers: `utilization`, `financials` and
 * `retainerDrawdown` over the time tracking client, among others.
 */
export function projectsOf(db: AppDb) {
  const { $blocks: blocks } = db;

  return createProjects({
    transport: rpcTransport(db.$client),
    parts: {
      tasks: defaultTasks(blocks.tasks),
      "time-entries": blocks.timeEntries,
      "billable-time": blocks.billableTime,
      approvals: blocks.approvals,
      invoices: blocks.invoices,
      meetings: blocks.meetings,
      comments: blocks.comments,
      attachments: blocks.attachments,
      tags: blocks.tags,
      timeline: blocks.timeline,
      relations: blocks.relations,
      "saved-views": blocks.savedViews,
      subjects: blocks.subjects,
    },
  });
}

/**
 * `saas.rotateApiKey` over the API keys client. This app installs the key block
 * without the billing part of `saas`, so it builds the one helper it uses.
 */
export function keyRotationOf(db: AppDb) {
  return createKeyRotator({ apiKeys: db.$blocks.apiKeys });
}

/**
 * The `sales` composite's helpers: `acceptQuote` and `billQuote` over the
 * deals, quotes, orders and invoices clients.
 */
export function salesOf(db: AppDb) {
  const { $blocks: blocks } = db;

  return createSales({
    transport: rpcTransport(db.$client),
    parts: {
      contacts: blocks.contacts,
      pipelines: blocks.pipelines,
      deals: blocks.deals,
      quotes: blocks.quotes,
      orders: blocks.orders,
      invoices: blocks.invoices,
    },
  });
}

/**
 * The `finance` composite's helpers: `closePeriod` and `reconcile` over the
 * accounting and banking clients.
 */
export function financeOf(db: AppDb) {
  const { $blocks: blocks } = db;

  return createFinance({
    transport: rpcTransport(db.$client),
    parts: {
      accounting: blocks.accounting,
      tax: blocks.tax,
      banking: blocks.banking,
      invoices: blocks.invoices,
    },
  });
}

/**
 * The `care` composite's helpers: `dossier` and `prescribeWithConsent` over the
 * clinical, consent and funding clients.
 */
export function careOf(db: AppDb) {
  const { $blocks: blocks } = db;

  return createCare({
    transport: rpcTransport(db.$client),
    parts: {
      contacts: blocks.contacts,
      guests: blocks.guests,
      "field-encryption": blocks.fieldEncryption,
      "data-lifecycle": blocks.dataLifecycle,
      consents: blocks.consents,
      activities: blocks.activities,
      "care-plans": blocks.carePlans,
      observations: blocks.observations,
      medications: blocks.medications,
      forms: blocks.forms,
      bookings: blocks.bookings,
      calendar: blocks.calendar,
      reminders: blocks.reminders,
      "time-entries": blocks.timeEntries,
      funding: blocks.funding,
      shifts: blocks.shifts,
      qualifications: blocks.qualifications,
      courses: blocks.courses,
      cases: blocks.cases,
      acknowledgements: blocks.acknowledgements,
      drive: blocks.drive,
      attachments: blocks.attachments,
      versions: blocks.versions,
      approvals: blocks.approvals,
      "state-machine": blocks.stateMachine,
      numbering: blocks.numbering,
      signatures: blocks.signatures,
    },
  });
}

/**
 * The `governance` composite's helper: `exportSubject` over the audit, field
 * history and data lifecycle clients.
 */
export function governanceOf(db: AppDb) {
  const { $blocks: blocks } = db;

  return createGovernance({
    transport: rpcTransport(db.$client),
    parts: {
      audit: blocks.audit,
      "field-history": blocks.fieldHistory,
      "data-lifecycle": blocks.dataLifecycle,
    },
  });
}

/**
 * The `recruiting` composite's `hire`: marks an application hired, then makes
 * the employee from it.
 */
export function recruitingOf(db: AppDb) {
  const { $blocks: blocks } = db;

  return createRecruiting({
    transport: rpcTransport(db.$client),
    parts: {
      hiring: blocks.hiring,
      employees: blocks.employees,
      calendar: blocks.calendar,
    },
  });
}

/**
 * The `people` composite's `onboard` and `offboard` over the employees, leave,
 * shifts, payroll export, qualifications and enrollments clients.
 */
export function peopleOf(db: AppDb) {
  const { $blocks: blocks } = db;

  return createPeople({
    transport: rpcTransport(db.$client),
    parts: {
      employees: blocks.employees,
      leave: blocks.leave,
      shifts: blocks.shifts,
      "payroll-export": blocks.payrollExport,
      qualifications: blocks.qualifications,
      enrollments: blocks.enrollments,
    },
  });
}

/** The `learning` composite's `assign` over the courses and enrollments clients. */
export function learningOf(db: AppDb) {
  const { $blocks: blocks } = db;

  return createLearning({
    transport: rpcTransport(db.$client),
    parts: { courses: blocks.courses, enrollments: blocks.enrollments },
  });
}

/**
 * The `scheduling` composite's `bookWithReminder` over the bookings, calendar
 * and reminders clients.
 */
export function schedulingOf(db: AppDb) {
  const { $blocks: blocks } = db;

  return createScheduling({
    transport: rpcTransport(db.$client),
    parts: {
      bookings: blocks.bookings,
      calendar: blocks.calendar,
      reminders: blocks.reminders,
    },
  });
}

/**
 * The `procurement` composite's helper: `payDueBills` batches the bills that
 * are due, posts the batch to the books and exports the bank file.
 */
export function procurementOf(db: AppDb) {
  const { $blocks: blocks } = db;

  return createProcurement({
    transport: rpcTransport(db.$client),
    parts: {
      rfqs: blocks.rfqs,
      inventory: blocks.inventory,
      invoices: blocks.invoices,
      banking: blocks.banking,
    },
  });
}
