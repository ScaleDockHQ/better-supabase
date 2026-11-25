"use server";

import { dbError, err, invalidInput, ok } from "better-supabase";
import { money } from "better-supabase/commerce";
import { refresh } from "next/cache";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import { API_KEYS_TAG } from "@/features/api-keys/api-keys-cache";
import { BANKING_TAG } from "@/features/banking/banking-cache";
import { BILLING_TAG } from "@/features/billing/billing-cache";
import { BOOKINGS_TAG } from "@/features/bookings/bookings-cache";
import { findBookingPage } from "@/features/bookings/bookings-queries";
import { CALENDAR_TAG } from "@/features/calendar/calendar-cache";
import { CASES_TAG } from "@/features/cases/cases-cache";
import { COURSES_TAG } from "@/features/courses/courses-cache";
import { CRM_TAG } from "@/features/crm/crm-cache";
import { CUSTOMERS_TAG } from "@/features/customers/customers-cache";
import { DRIVE_TAG } from "@/features/drive/drive-cache";
import { driveOf } from "@/features/drive/drive-client";
import { DRIVE_ROLES } from "@/features/drive/drive-roles";
import { FIELD_TAG } from "@/features/field/field-cache";
import { FINANCE_RECORDS_TAG } from "@/features/finance-records/finance-records-cache";
import { MAINTENANCE_TAG } from "@/features/maintenance/maintenance-cache";
import { ONBOARDING_TAG } from "@/features/onboarding/onboarding-cache";
import { PEOPLE_TAG } from "@/features/people/people-cache";
import { PRIVACY_TAG } from "@/features/privacy/privacy-cache";
import { PROJECTS_TAG } from "@/features/projects/projects-cache";
import { SHOP_TAG } from "@/features/shop/shop-cache";
import { present } from "@/lib/present";
import { refreshCaller } from "@/lib/refresh-caller";
import { blockSet } from "@/lib/supabase";
import { bsb } from "@/lib/supabase/server";

import {
  careOf,
  commerceOf,
  crmOf,
  filespaceOf,
  governanceOf,
  keyRotationOf,
  financeOf,
  learningOf,
  peopleOf,
  procurementOf,
  projectsOf,
  recruitingOf,
  salesOf,
  schedulingOf,
  supportOf,
} from "./composites";

const Id = v.pipe(v.string(), v.uuid());
const Hours = v.pipe(v.number(), v.integer(), v.minValue(0), v.maxValue(720));

/**
 * Wins a deal and drafts its quote in one call: `crm.closeWon`. The deal is won
 * first, so a refused move leaves no quote behind.
 */
export const closeDealWon = bsb.action(
  {
    input: v.object({ dealId: Id, quote: v.optional(v.boolean(), true) }),
    requireTenant: true,
    permission: "deals.write",
  },
  async ({ dealId, quote }, { db, auth }) => {
    const closed = await crmOf(db).closeWon({ dealId, quote });

    if (!closed.ok) {
      return closed;
    }

    await refreshCaller(auth, [CRM_TAG, CUSTOMERS_TAG]);

    return ok({
      dealId: closed.data.deal.id,
      quoteId: closed.data.quote?.id ?? null,
    });
  },
);

/**
 * Makes a link anyone with the token can open for a drive item, valid for
 * `days`: `filespace.publicLink`.
 */
export const createPublicLink = bsb.action(
  {
    input: v.object({
      id: Id,
      days: v.pipe(v.number(), v.integer(), v.minValue(1), v.maxValue(90)),
    }),
    requireTenant: true,
    permission: "drive.read",
  },
  async ({ id, days }, { db }) => {
    const link = await filespaceOf(db, driveOf(db)).publicLink({
      id,
      expiresAt: Temporal.Now.instant().add({ hours: days * 24 }),
    });

    if (!link.ok) {
      return link;
    }

    return ok({ token: link.data.token });
  },
);

/**
 * Shares a drive item with each of the given membership roles and reports per
 * role: `filespace.bulkShare`. A refused role lands in `failed` and the others
 * still run.
 */
export const shareDriveWithRoles = bsb.action(
  {
    input: v.object({
      id: Id,
      roles: v.pipe(
        v.array(v.pipe(v.string(), v.minLength(1))),
        v.minLength(1),
      ),
      role: v.picklist(DRIVE_ROLES),
    }),
    requireTenant: true,
    permission: "drive.read",
  },
  async ({ id, roles, role }, { db, auth }) => {
    const report = await filespaceOf(db, driveOf(db)).bulkShare({
      id,
      principals: roles.map((each) => ({
        principal: { type: "role", id: each },
        role,
      })),
    });

    if (!report.ok) {
      return report;
    }

    await refreshCaller(auth, [DRIVE_TAG]);

    return ok({
      shared: report.data.succeeded.length,
      failed: report.data.failed.length,
    });
  },
);

/**
 * Picks an owner for a contact from the assignment queues, with the contact's
 * segments as territory fields: `crm.route`.
 */
export const routeContact = bsb.action(
  {
    input: v.object({ contactId: Id }),
    requireTenant: true,
    permission: "assignment.assign",
  },
  async ({ contactId }, { db, tenant }) => {
    const routed = await crmOf(db).route({
      organizationId: tenant,
      subject: { type: "contact", id: contactId },
    });

    if (!routed.ok) {
      return routed;
    }

    return ok({
      userId: routed.data.assignment?.userId ?? null,
      segments: routed.data.segments.map((segment) => segment.name),
    });
  },
);

/** How the running sales targets stand against the period: `crm.attainment`. */
export const salesAttainment = bsb.action(
  { input: v.object({}), requireTenant: true, permission: "goals.read" },
  async (_input, { db, tenant }) => {
    const result = await crmOf(db).attainment({ organizationId: tenant });

    if (!result.ok) {
      return result;
    }

    return ok({
      pace: result.data.pace,
      behind: result.data.behind.map((target) => target.name),
      byMetric: result.data.byMetric.map((entry) => ({
        metric: entry.metric,
        attainment: entry.attainment,
      })),
    });
  },
);

/**
 * Rotates an API key and keeps the old token working for `graceHours`:
 * `saas.rotateApiKey`.
 */
export const rotateKey = bsb.action(
  {
    input: v.object({ id: Id, graceHours: v.optional(Hours) }),
    requireTenant: true,
    permission: "api_keys.manage",
  },
  async ({ id, graceHours }, { db, auth }) => {
    const rotated = await keyRotationOf(db).rotateApiKey({ id, graceHours });

    if (!rotated.ok) {
      return rotated;
    }

    await refreshCaller(auth, [API_KEYS_TAG]);

    return ok({ id: rotated.data.key.id, token: rotated.data.token });
  },
);

/**
 * Invites a teammate when the plan has a seat left, in one database call:
 * `organizations.inviteWithinSeats` counts the members against the `seats`
 * entitlement and writes the invitation in one transaction (ADR 1235).
 */
export const inviteWithinSeats = bsb.action(
  {
    input: v.object({
      email: v.pipe(v.string(), v.trim(), v.toLowerCase(), v.email()),
      role: v.pipe(v.string(), v.minLength(1), v.maxLength(100)),
    }),
    requireTenant: true,
    permission: "members.invite",
  },
  async ({ email, role }, { db, tenant }) => {
    const sent = await blockSet
      .client(db, "organizations")
      .inviteWithinSeats({ organizationId: tenant, email, role });

    if (!sent.ok) {
      return sent;
    }

    refresh();

    return ok({ id: sent.data.invitation.id });
  },
);

/**
 * Hands a ticket to new assignees and restarts its SLA clocks at a higher
 * priority: `support.escalate`.
 */
export const escalateTicket = bsb.action(
  {
    input: v.object({
      ticketId: Id,
      assigneeIds: v.pipe(v.array(Id), v.minLength(1)),
      priority: v.pipe(v.string(), v.minLength(1)),
    }),
    requireTenant: true,
    permission: "tasks.write",
  },
  async (input, { db }) => {
    const escalated = await supportOf(db).escalate(input);

    if (!escalated.ok) {
      return escalated;
    }

    return ok({
      assignees: escalated.data.assignees,
      clocks: escalated.data.clocks.length,
    });
  },
);

/**
 * Settles a return as restock, quarantine or reject, with an optional refund:
 * `commerce.processReturn`.
 */
export const settleReturn = bsb.action(
  {
    input: v.object({
      orderId: Id,
      returnId: Id,
      disposition: v.picklist(["restock", "quarantine", "reject"]),
      refund: v.optional(
        v.union([
          v.boolean(),
          v.pipe(
            v.picklist(["true", "false"]),
            v.transform((value) => value === "true"),
          ),
        ]),
        false,
      ),
    }),
    requireTenant: true,
    permission: "orders.manage",
  },
  async ({ orderId, returnId, disposition, refund }, { db, auth }) => {
    const settled = await commerceOf(db).processReturn({
      orderId,
      returnId,
      disposition,
      refund: refund ? true : undefined,
    });

    if (!settled.ok) {
      return settled;
    }

    await refreshCaller(auth, FINANCE_TAGS);

    return ok({
      disposition: settled.data.disposition,
      refunded: settled.data.refund !== null,
    });
  },
);

/** The week's tracked hours per member: `projects.utilization`. */
export const weekUtilization = bsb.action(
  {
    input: v.object({ weekOf: v.pipe(v.string(), v.isoDate()) }),
    requireTenant: true,
    permission: "time_entries.read",
  },
  async ({ weekOf }, { db }) => {
    const result = await projectsOf(db).utilization({
      weekOf: Temporal.PlainDate.from(weekOf),
    });

    if (!result.ok) {
      return result;
    }

    return ok(
      result.data.members.map((member) => ({
        userId: member.userId,
        utilization: member.utilization,
        billableUtilization: member.billableUtilization,
      })),
    );
  },
);

/**
 * Approves a submitted week and invoices the unbilled time:
 * `projects.approveAndInvoice`. A refused approval invoices nothing.
 */
export const approveAndInvoiceTimesheet = bsb.action(
  {
    input: v.object({
      timesheetId: Id,
      title: v.optional(v.pipe(v.string(), v.trim(), v.maxLength(120))),
    }),
    requireTenant: true,
    permission: "time_entries.approve",
  },
  async ({ timesheetId, title }, { db, auth }) => {
    const done = await projectsOf(db).approveAndInvoice({
      timesheetId,
      invoice: title === undefined || title === "" ? undefined : { title },
    });

    if (!done.ok) {
      return done;
    }

    await refreshCaller(auth, [PROJECTS_TAG, FINANCE_RECORDS_TAG]);

    return ok({
      timesheetId: done.data.timesheet.id ?? timesheetId,
      invoiceId: done.data.invoice.invoiceId,
    });
  },
);

/**
 * The hours on a project and how much of its retainer they used:
 * `projects.financials` and `projects.retainerDrawdown`.
 */
export const projectBudget = bsb.action(
  {
    input: v.object({
      projectId: Id,
      retainerAmount: v.optional(
        v.pipe(v.number(), v.integer(), v.minValue(0)),
      ),
      currency: v.optional(v.pipe(v.string(), v.length(3)), "EUR"),
    }),
    requireTenant: true,
    permission: "time_entries.read",
  },
  async ({ projectId, retainerAmount, currency }, { db }) => {
    const projects = projectsOf(db);
    const financials = await projects.financials({ projectId });

    if (!financials.ok) {
      return financials;
    }

    const drawdown =
      retainerAmount === undefined
        ? null
        : await projects.retainerDrawdown({
            projectId,
            retainer: money(BigInt(retainerAmount), currency),
          });

    if (drawdown !== null && !drawdown.ok) {
      return drawdown;
    }

    return ok({
      hours: financials.data.seconds / 3600,
      billableHours: financials.data.billableSeconds / 3600,
      remaining: drawdown?.data.remaining.amount.toString() ?? null,
      exhausted: drawdown?.data.exhausted ?? false,
    });
  },
);

/** Loses a deal and withdraws the quotes named in `withdraw`: `crm.closeLost`. */
export const closeDealLost = bsb.action(
  {
    input: v.object({
      dealId: Id,
      reason: v.optional(v.pipe(v.string(), v.trim(), v.maxLength(500))),
      withdraw: v.optional(v.array(Id), []),
    }),
    requireTenant: true,
    permission: "deals.write",
  },
  async ({ dealId, reason, withdraw }, { db, auth }) => {
    const closed = await crmOf(db).closeLost({
      dealId,
      reason: reason === "" ? undefined : reason,
      withdraw,
    });

    if (!closed.ok) {
      return closed;
    }

    await refreshCaller(auth, [CRM_TAG, CUSTOMERS_TAG]);

    return ok({
      dealId: closed.data.deal.id,
      withdrawn: closed.data.withdrawn,
    });
  },
);

/**
 * Records the customer's acceptance of a quote, wins its deal and creates the
 * order: `sales.acceptQuote`.
 */
export const acceptQuote = bsb.action(
  {
    input: v.object({
      quoteId: Id,
      dealId: v.optional(Id),
      followUp: v.optional(v.picklist(["order", "invoice"]), "order"),
    }),
    requireTenant: true,
    permission: "quotes.write",
  },
  async ({ quoteId, dealId, followUp }, { db, auth }) => {
    const accepted = await salesOf(db).acceptQuote({
      quoteId,
      dealId,
      // oxlint-disable-next-line unicorn/no-thenable -- `then` is the composite's own input key (1 finding)
      then: followUp,
    });

    if (!accepted.ok) {
      return accepted;
    }

    await refreshCaller(auth, [CRM_TAG, CUSTOMERS_TAG]);

    return ok({
      quoteId: accepted.data.quote.id,
      orderId: accepted.data.order?.id ?? null,
      invoiceId: accepted.data.invoice?.id ?? null,
    });
  },
);

/** Marks an order paid and ships all of it: `commerce.payAndFulfil`. */
export const payAndFulfilOrder = bsb.action(
  {
    input: v.object({ orderId: Id }),
    requireTenant: true,
    permission: "orders.manage",
  },
  async ({ orderId }, { db, auth }) => {
    const done = await commerceOf(db).payAndFulfil({ orderId });

    if (!done.ok) {
      return done;
    }

    await refreshCaller(auth, [CUSTOMERS_TAG, SHOP_TAG]);

    return ok({ shipped: done.data.fulfillment.shipped });
  },
);

/**
 * Matches an account's open bank transactions to their best invoice:
 * `finance.reconcile`.
 */
export const reconcileAccount = bsb.action(
  {
    input: v.object({ accountId: Id }),
    requireTenant: true,
    permission: "banking.reconcile",
  },
  async ({ accountId }, { db, auth }) => {
    const run = await financeOf(db).reconcile({ accountId });

    if (!run.ok) {
      return run;
    }

    await refreshCaller(auth, [CUSTOMERS_TAG]);

    return ok({
      matched: run.data.matched.length,
      unmatched: run.data.unmatched.length,
      failed: run.data.failed.length,
    });
  },
);

// Service and logistics

/** An empty form field is `""`; it means "not given". */
const Blank = v.pipe(
  v.optional(v.string(), ""),
  v.trim(),
  v.maxLength(2000),
  v.transform((value) => (value === "" ? undefined : value)),
);

const Quantity = v.pipe(
  v.optional(v.string(), ""),
  v.trim(),
  v.transform((value) => (value === "" ? undefined : value)),
  v.check(
    (value) => value === undefined || /^\d+(\.\d{1,3})?$/u.test(value),
    "Enter a number with at most three decimals",
  ),
);

/**
 * Closes a visit: records the part used and the meter reading taken, then marks
 * the work order done with the note: `service.completeVisit`. The status moves
 * last, so a failed part or reading leaves the work order open.
 */
export const completeVisit = bsb.action(
  {
    input: v.object({
      workOrderId: Id,
      note: Blank,
      partName: Blank,
      partQuantity: Quantity,
      meterId: Blank,
      reading: Quantity,
    }),
    requireTenant: true,
    permission: "dispatch.work",
  },
  async (
    { workOrderId, note, partName, partQuantity, meterId, reading },
    { db, auth },
  ) => {
    const visit = await db.$blocks.service.completeVisit({
      workOrderId,
      note,
      parts:
        partName === undefined
          ? []
          : [{ name: partName, quantity: partQuantity ?? "1" }],
      readings:
        meterId === undefined || reading === undefined
          ? []
          : [{ meterId, value: reading }],
    });

    if (!visit.ok) {
      return visit;
    }

    await refreshCaller(auth, [FIELD_TAG, MAINTENANCE_TAG]);

    return ok({
      workOrderId: visit.data.workOrder.id,
      parts: visit.data.parts,
      readings: visit.data.readings,
    });
  },
);

const Text = v.pipe(v.string(), v.trim(), v.minLength(1));

/**
 * Opens a support ticket as a task and starts its SLA clocks:
 * `support.openTicket`.
 */
export const openTicket = bsb.action(
  {
    input: v.object({ title: Text, body: Blank }),
    requireTenant: true,
    permission: "tasks.write",
  },
  async ({ title, body }, { db, auth, tenant }) => {
    // `support.openTicket` starts the clocks on a `task` subject, and this app
    // names the entity `work_item` (finding 4): the same two calls, by hand.
    const created = await db.$blocks.tasks.create({
      organizationId: tenant,
      input: body === undefined ? { title } : { title, body },
    });

    if (!created.ok) {
      return created;
    }

    const clocks = await db.$blocks.sla.start({
      subject: { type: "work_item", id: created.data.id },
    });

    if (!clocks.ok) {
      return clocks;
    }

    await refreshCaller(auth, [PROJECTS_TAG, CASES_TAG]);

    return ok({ id: created.data.id, clocks: clocks.data.length });
  },
);

/** Posts a comment on a case: `collaboration.discuss`. */
export const discussCase = bsb.action(
  {
    input: v.object({ caseId: Id, comment: Text }),
    requireTenant: true,
    permission: "cases.read",
  },
  async ({ caseId, comment }, { db, auth }) => {
    const discussion = await db.$blocks.collaboration.discuss({
      subject: { type: "case", id: caseId },
      comment: { body: comment },
    });

    if (!discussion.ok) {
      return discussion;
    }

    await refreshCaller(auth, [CASES_TAG, CRM_TAG, CUSTOMERS_TAG]);

    return ok({ caseId });
  },
);

const Time = v.pipe(v.string(), v.regex(/^([01]\d|2[0-3]):[0-5]\d$/));

/**
 * Prescribes a medication only while the client's consent for the purpose is
 * active: `care.prescribeWithConsent`. Without the consent it returns the
 * consent error and prescribes nothing.
 */
export const prescribeMedicationWithConsent = bsb.action(
  {
    input: v.object({
      clientId: Id,
      medicationId: Id,
      purposeKey: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(80)),
      dose: v.pipe(
        v.string(),
        v.transform(Number),
        v.number(),
        v.minValue(0.001),
      ),
      times: v.pipe(
        v.string(),
        v.transform((value) =>
          value
            .split(",")
            .map((time) => time.trim())
            .filter((time) => time !== ""),
        ),
        v.array(Time),
        v.minLength(1),
      ),
    }),
    requireTenant: true,
    permission: "medications.prescribe",
  },
  async (
    { clientId, medicationId, purposeKey, dose, times },
    { db, auth, tenant },
  ) => {
    const prescribed = await careOf(db).prescribeWithConsent({
      organizationId: tenant,
      subject: { type: "customer", id: clientId },
      purposeKey,
      medicationId,
      order: { dose, schedule: { times } },
    });

    if (!prescribed.ok) {
      return prescribed;
    }

    await refreshCaller(auth, [CUSTOMERS_TAG]);

    return ok({ orderId: prescribed.data.id });
  },
);

/**
 * Requests the export of one record and writes the audit entry that records it:
 * `governance.exportSubject`.
 */
export const exportRecordSubject = bsb.action(
  {
    input: v.object({
      subjectType: v.pipe(
        v.string(),
        v.trim(),
        v.minLength(1),
        v.maxLength(60),
      ),
      subjectId: Id,
    }),
    requireTenant: true,
    permission: "data_lifecycle.export",
  },
  async ({ subjectType, subjectId }, { db, auth, tenant }) => {
    const exported = await governanceOf(db).exportSubject({
      organizationId: tenant,
      subjectType,
      subjectId,
    });

    if (!exported.ok) {
      return exported;
    }

    await refreshCaller(auth, [PRIVACY_TAG]);

    return ok({
      exportId: exported.data.export.id,
      auditId: exported.data.auditId,
    });
  },
);

// People

const PlainDate = v.pipe(
  v.optional(v.string(), ""),
  v.trim(),
  v.transform((value) => (value === "" ? undefined : value)),
  v.check(
    (value) => value === undefined || /^\d{4}-\d{2}-\d{2}$/u.test(value),
    "Enter a date",
  ),
);

/**
 * Hires an application and makes the employee from it: `recruiting.hire`. The
 * application is marked hired first and the employee is created once, so a
 * retry finishes a hire that stopped in the middle.
 */
export const hireApplication = bsb.action(
  {
    input: v.object({
      applicationId: Id,
      jobTitle: Blank,
      startDate: PlainDate,
    }),
    requireTenant: true,
    permission: "hiring.manage",
  },
  async ({ applicationId, jobTitle, startDate }, { db, auth }) => {
    const hired = await recruitingOf(db).hire({
      applicationId,
      overrides: present({
        jobTitle,
        startDate:
          startDate === undefined
            ? undefined
            : Temporal.PlainDate.from(startDate),
      }),
    });

    if (!hired.ok) {
      return hired;
    }

    await refreshCaller(auth, [PEOPLE_TAG, ONBOARDING_TAG, CUSTOMERS_TAG]);

    return ok({ id: hired.data.employee.id });
  },
);

/**
 * Creates an employee and starts them on an onboarding program:
 * `people.onboard`. A failed enrollment leaves the employee created and returns
 * its error.
 */
export const onboardEmployee = bsb.action(
  {
    input: v.object({
      name: Text,
      email: Blank,
      jobTitle: Blank,
      program: v.pipe(v.string(), v.minLength(1)),
      startDate: PlainDate,
    }),
    requireTenant: true,
    permission: "employees.write",
  },
  async (
    { name, email, jobTitle, program, startDate },
    { db, auth, tenant },
  ) => {
    const onboarded = await peopleOf(db).onboard({
      organizationId: tenant,
      program,
      employee: {
        name,
        ...present({
          email,
          jobTitle,
          startDate:
            startDate === undefined
              ? undefined
              : Temporal.PlainDate.from(startDate),
        }),
      },
      ...present({
        dates:
          startDate === undefined
            ? undefined
            : {
                startsAt: Temporal.PlainDate.from(startDate)
                  .toZonedDateTime("UTC")
                  .toInstant(),
              },
      }),
    });

    if (!onboarded.ok) {
      return onboarded;
    }

    await refreshCaller(auth, [PEOPLE_TAG, ONBOARDING_TAG]);

    return ok({ id: onboarded.data.employee.id });
  },
);

/**
 * Ends an employment: `people.offboard` sets the end date, then cancels the
 * employee's active onboarding runs and releases their open shifts of the next
 * month.
 */
export const offboardEmployee = bsb.action(
  {
    input: v.object({ employeeId: Id, endDate: PlainDate, reason: Blank }),
    requireTenant: true,
    permission: "employees.write",
  },
  async ({ employeeId, endDate, reason }, { db, auth, tenant }) => {
    const employee = await db.employees.get(employeeId);

    if (!employee.ok) {
      return employee;
    }

    const today = Temporal.Now.plainDateISO();

    const [runs, roster] = await Promise.all([
      db.enrollments.enrollmentPage({
        filters: { subjectType: ["employee"], subjectId: [employeeId] },
        limit: 50,
      }),
      db.shifts.roster({
        organizationId: tenant,
        from: today,
        until: today.add({ days: 30 }),
      }),
    ]);

    if (!runs.ok) {
      return runs;
    }

    if (!roster.ok) {
      return roster;
    }

    const userId = employee.data.userId;

    const offboarded = await peopleOf(db).offboard({
      employeeId,
      ...present({
        endDate:
          endDate === undefined ? undefined : Temporal.PlainDate.from(endDate),
        reason,
      }),
      enrollmentIds: runs.data.items
        .filter((run) => run.status === "active")
        .map((run) => run.id),
      assignmentIds:
        userId === undefined
          ? []
          : roster.data.flatMap((shift) =>
              shift.assignments
                .filter(
                  (assignment) =>
                    assignment.userId === userId &&
                    (assignment.status === "assigned" ||
                      assignment.status === "requested"),
                )
                .map((assignment) => assignment.id),
            ),
    });

    if (!offboarded.ok) {
      return offboarded;
    }

    await refreshCaller(auth, [PEOPLE_TAG, ONBOARDING_TAG]);

    return ok({ id: employeeId });
  },
);

/** Puts a member in a course: `learning.assign`. */
export const assignCourse = bsb.action(
  {
    input: v.object({ courseId: Id, userId: Id }),
    requireTenant: true,
    permission: "courses.enroll",
  },
  async ({ courseId, userId }, { db, auth }) => {
    const assigned = await learningOf(db).assign({ courseId, userId });

    if (!assigned.ok) {
      return assigned;
    }

    await refreshCaller(auth, [COURSES_TAG]);

    return ok({ id: assigned.data.learner.enrollmentId });
  },
);

const Hour = v.picklist(["09", "10", "11", "13", "14", "15", "16"]);

/**
 * Books a welcome meeting for a new hire on the caller's booking page and sets
 * the caller's reminder an hour before it: `scheduling.bookWithReminder`.
 */
export const bookWithReminder = bsb.action(
  {
    input: v.object({
      name: Text,
      email: Blank,
      date: v.pipe(v.string(), v.regex(/^\d{4}-\d{2}-\d{2}$/u)),
      hour: Hour,
    }),
    requireTenant: true,
    permission: "bookings.manage",
  },
  async ({ name, email, date, hour }, { db, auth, tenant, session }) => {
    if (session.kind !== "user") {
      return err(
        dbError("forbidden", "Sign in to book on your own booking page."),
      );
    }

    const page = await findBookingPage(db, tenant, session.user.id);

    if (!page) {
      return err(
        dbError(
          "not_found",
          "Set up your booking page under Availability first.",
        ),
      );
    }

    const booked = await schedulingOf(db).bookWithReminder({
      serviceId: page.serviceId,
      resourceId: page.resourceId,
      startsAt: Temporal.PlainDateTime.from(`${date}T${hour}:00`)
        .toZonedDateTime(page.tz)
        .toInstant(),
      customer: { name, ...present({ email }) },
      reminder: 60,
    });

    if (!booked.ok) {
      return booked;
    }

    await refreshCaller(auth, [BOOKINGS_TAG, CALENDAR_TAG]);

    return ok({ id: booked.data.booking.id });
  },
);

const FINANCE_TAGS = [FINANCE_RECORDS_TAG, BILLING_TAG, BANKING_TAG, SHOP_TAG];

/**
 * Closes an accounting period when nothing blocks it: `finance.closePeriod`. A
 * period with blockers stays open and the action returns them as the error, so
 * the page can list what to fix first.
 */
export const closeAccountingPeriod = bsb.action(
  {
    input: v.object({ periodId: Id }),
    requireTenant: true,
    permission: "accounting.manage",
  },
  async ({ periodId }, { db, auth }) => {
    const closed = await financeOf(db).closePeriod(periodId);

    if (!closed.ok) {
      return closed;
    }

    if (!closed.data.closed) {
      return err(
        invalidInput(
          `The period can't close yet: ${closed.data.blockers.join(" ")}`,
          closed.data.blockers.map((blocker) => ({
            path: ["periodId"],
            code: "PERIOD_BLOCKED",
            message: blocker,
          })),
        ),
      );
    }

    await refreshCaller(auth, FINANCE_TAGS);

    return ok({ id: closed.data.period.id, status: closed.data.period.status });
  },
);

/**
 * Pays the supplier bills due by a day in one batch: `procurement.payDueBills`
 * creates the batch, posts it to the books and exports the SEPA file. The bank
 * details of the suppliers come from the dialog, one IBAN for every supplier of
 * the run.
 */
export const payDueBills = bsb.action(
  {
    input: v.object({
      accountId: Id,
      dueBy: v.pipe(v.string(), v.isoDate()),
      creditorName: v.pipe(
        v.string(),
        v.trim(),
        v.minLength(1),
        v.maxLength(70),
      ),
      creditorIban: v.pipe(
        v.string(),
        v.trim(),
        v.minLength(8),
        v.maxLength(34),
      ),
    }),
    requireTenant: true,
    permission: "banking.manage",
  },
  async (
    { accountId, dueBy, creditorName, creditorIban },
    { db, tenant, auth },
  ) => {
    const bills = await db.invoices.page({
      organizationId: tenant,
      limit: 200,
    });

    if (!bills.ok) {
      return bills;
    }

    const creditors = Object.fromEntries(
      bills.data.items.flatMap((bill) =>
        bill.direction === "purchase" && bill.company
          ? [[bill.company.id, { name: creditorName, iban: creditorIban }]]
          : [],
      ),
    );

    const paid = await procurementOf(db).payDueBills({
      batch: { accountId, dueBy: Temporal.PlainDate.from(dueBy), creditors },
      sepa: {},
    });

    if (!paid.ok) {
      return paid;
    }

    await refreshCaller(auth, FINANCE_TAGS);

    return ok({ id: paid.data.batch.id, sepa: paid.data.sepa !== null });
  },
);

/** Asks for the return of every unit of an order: `orders.requestReturn`. */
export const requestOrderReturn = bsb.action(
  {
    input: v.object({
      orderId: Id,
      reason: v.optional(v.pipe(v.string(), v.trim(), v.maxLength(500))),
    }),
    requireTenant: true,
    permission: "orders.manage",
  },
  async ({ orderId, reason }, { db, auth }) => {
    const order = await db.orders.getOrder(orderId);

    if (!order.ok) {
      return order;
    }

    const requested = await db.orders.requestReturn({
      orderId,
      lines: order.data.lines.map((line) => ({
        lineId: line.id,
        quantity: line.quantity,
      })),
      reason: reason === "" ? undefined : reason,
    });

    if (!requested.ok) {
      return requested;
    }

    await refreshCaller(auth, [SHOP_TAG]);

    return ok({ id: requested.data.id, quantity: requested.data.quantity });
  },
);
