"use server";

import { ok } from "better-supabase";
import { money } from "better-supabase/commerce";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import { driveOf } from "@/features/drive/drive-client";
import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import {
  commerceOf,
  crmOf,
  filespaceOf,
  keyRotationOf,
  projectsOf,
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

    await refreshCaller(auth);

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
  async ({ id, graceHours }, { db }) => {
    const rotated = await keyRotationOf(db).rotateApiKey({ id, graceHours });

    if (!rotated.ok) {
      return rotated;
    }

    return ok({ id: rotated.data.key.id, token: rotated.data.token });
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
      refund: v.optional(v.boolean(), false),
    }),
    requireTenant: true,
    permission: "orders.manage",
  },
  async ({ orderId, returnId, disposition, refund }, { db }) => {
    const settled = await commerceOf(db).processReturn({
      orderId,
      returnId,
      disposition,
      refund: refund ? true : undefined,
    });

    if (!settled.ok) {
      return settled;
    }

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
    permission: "time_tracking.read",
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
    permission: "time_tracking.read",
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
