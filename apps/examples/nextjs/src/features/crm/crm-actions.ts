"use server";

import { dbError, err, ok } from "better-supabase";
import { parseMoney } from "better-supabase/commerce";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

const Id = v.pipe(v.string(), v.uuid());
const Name = v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200));

/** An empty form field is `""`; it means "not given". */
const Optional = v.pipe(
  v.optional(v.string(), ""),
  v.trim(),
  v.maxLength(2000),
  v.transform((value) => (value === "" ? undefined : value)),
);

const Currency = v.picklist(["EUR", "USD", "GBP"]);

/** A decimal with at most 2 places, the minor units of EUR, USD and GBP. */
const Decimal = v.pipe(v.string(), v.trim(), v.regex(/^\d+(\.\d{1,2})?$/u));
const IsoDate = v.pipe(v.string(), v.isoDate());

/** Creates a company or a person and returns where it lives. */
export const createContact = bsb.action(
  {
    input: v.object({
      kind: v.picklist(["company", "person"]),
      name: Name,
      email: Optional,
      domain: Optional,
    }),
    requireTenant: true,
    permission: "contacts.write",
  },
  async ({ kind, name, email, domain }, { tenant, db, auth }) => {
    const { contacts: parties } = db.$blocks;

    const saved =
      kind === "company"
        ? await parties.saveCompany(tenant, { name, domain: domain ?? null })
        : await parties.savePerson(tenant, { name, email: email ?? null });

    if (!saved.ok) {
      return saved;
    }

    await refreshCaller(auth);

    return ok({ id: saved.data.id, name: saved.data.name });
  },
);

/** Adds a person to a company, with an optional role. */
export const linkPerson = bsb.action(
  {
    input: v.object({ companyId: Id, personId: Id, role: Optional }),
    requireTenant: true,
    permission: "contacts.write",
  },
  async ({ companyId, personId, role }, { db, auth }) => {
    const linked = await db.$blocks.contacts.linkPerson(
      companyId,
      personId,
      role ? { role } : {},
    );

    if (!linked.ok) {
      return linked;
    }

    await refreshCaller(auth);

    return ok(true);
  },
);

/** Logs a call, email, meeting or note on a contact or a care client. */
export const logActivity = bsb.action(
  {
    input: v.object({
      subjectType: v.picklist(["company", "person", "customer"]),
      subjectId: Id,
      type: v.picklist(["call", "email", "meeting", "note"]),
      title: Name,
      body: Optional,
    }),
    requireTenant: true,
    permission: "activities.write",
  },
  async (
    { subjectType, subjectId, type, title, body },
    { tenant, db, auth },
  ) => {
    const logged = await db.activities.log(
      tenant,
      {
        type,
        title,
        body: body ?? null,
        // Logged after it happened, so it is done rather than an open task.
        doneAt: type === "note" ? null : Temporal.Now.instant(),
      },
      [{ type: subjectType, id: subjectId }],
    );

    if (!logged.ok) {
      return logged;
    }

    await refreshCaller(auth);

    return ok({ id: logged.data.id });
  },
);

const DEFAULT_STAGES = [
  { key: "qualified", name: "Qualified", category: "open", probability: 20 },
  { key: "discovery", name: "Discovery", category: "open", probability: 35 },
  { key: "proposal", name: "Proposal", category: "open", probability: 55 },
  {
    key: "negotiation",
    name: "Negotiation",
    category: "open",
    probability: 75,
  },
  { key: "won", name: "Closed won", category: "won", probability: 100 },
  { key: "lost", name: "Closed lost", category: "lost", probability: 0 },
] as const;

/** Creates the "Sales" deal pipeline with six stages, unless one exists. */
export const createDefaultPipeline = bsb.action(
  { requireTenant: true, permission: "pipelines.manage" },
  async (_input, { tenant, db, auth }) => {
    const { pipelines } = db;
    const existing = await pipelines.list(tenant, "deal");

    if (!existing.ok) {
      return existing;
    }

    const found = existing.data[0];

    if (found) {
      return ok({ id: found.id });
    }

    const pipeline = await pipelines.upsert(tenant, {
      subjectType: "deal",
      key: "sales",
      name: "Sales",
      isDefault: true,
    });

    if (!pipeline.ok) {
      return pipeline;
    }

    // In order: each stage is added at the end of the board.
    for (const stage of DEFAULT_STAGES) {
      const saved = await pipelines.saveStage(pipeline.data.id, stage);

      if (!saved.ok) {
        return saved;
      }
    }

    await refreshCaller(auth);

    return ok({ id: pipeline.data.id });
  },
);

/** Creates a deal in a stage of the pipeline. */
export const createDeal = bsb.action(
  {
    input: v.object({
      name: Name,
      amount: Decimal,
      currency: Currency,
      closeOn: IsoDate,
      pipelineId: Id,
      stageId: Id,
    }),
    requireTenant: true,
    permission: "deals.write",
  },
  async (
    { name, amount, currency, closeOn, pipelineId, stageId },
    { tenant, db, auth },
  ) => {
    const created = await db.deals.create(tenant, {
      name,
      closeOn: Temporal.PlainDate.from(closeOn),
      amount: parseMoney(amount, currency),
      currency,
      pipelineId,
      stageId,
    });

    if (!created.ok) {
      return created;
    }

    await refreshCaller(auth);

    return ok({ id: created.data.id, identifier: created.data.identifier });
  },
);

/** Moves a deal to another stage; the deals block checks the transition. */
export const moveDeal = bsb.action(
  {
    input: v.object({ dealId: Id, stageId: Id }),
    requireTenant: true,
    permission: "deals.write",
  },
  async ({ dealId, stageId }, { db, auth }) => {
    const moved = await db.deals.update([
      { dealId, field: "stageId", value: stageId },
    ]);

    if (!moved.ok) {
      return moved;
    }

    const [rejected] = moved.data.rejected;

    if (rejected) {
      return err(dbError("raised", rejected.reason));
    }

    await refreshCaller(auth);

    return ok(true);
  },
);

/** Creates a target for won deals in a period. */
export const createTarget = bsb.action(
  {
    input: v.object({
      name: Name,
      metric: v.picklist(["deals.won_amount", "deals.won_count"]),
      goal: Decimal,
      currency: Currency,
      periodStart: IsoDate,
      periodEnd: IsoDate,
    }),
    requireTenant: true,
    permission: "goals.manage",
  },
  async (
    { name, metric, goal, currency, periodStart, periodEnd },
    { tenant, db, auth },
  ) => {
    const amount = metric === "deals.won_amount";

    if (!amount && goal.includes(".")) {
      return err(dbError("invalid_input", "A count goal is a whole number"));
    }

    const target = {
      name,
      metric,
      periodStart: Temporal.PlainDate.from(periodStart),
      periodEnd: Temporal.PlainDate.from(periodEnd),
    };

    const saved = await db.goals.upsert(
      tenant,
      amount
        ? { ...target, goal: parseMoney(goal, currency).amount, currency }
        : { ...target, goal: BigInt(goal) },
    );

    if (!saved.ok) {
      return saved;
    }

    await refreshCaller(auth);

    return ok({ id: saved.data.id });
  },
);

/** Creates an empty draft quote; the builder adds its lines. */
export const createQuote = bsb.action(
  {
    input: v.object({ title: Name, currency: Currency }),
    requireTenant: true,
    permission: "quotes.write",
  },
  async ({ title, currency }, { tenant, db, auth }) => {
    const created = await db.quotes.create(tenant, { title, currency });

    if (!created.ok) {
      return created;
    }

    await refreshCaller(auth);

    return ok({ id: created.data.id });
  },
);

const QuoteLine = v.object({
  description: Name,
  quantity: v.pipe(v.number(), v.integer(), v.minValue(1)),
  unitAmount: Decimal,
  discountPercent: v.pipe(v.number(), v.minValue(0), v.maxValue(100)),
  taxPercent: v.pipe(v.number(), v.minValue(0), v.maxValue(100)),
});

/** Replaces a draft's lines; the database computes the totals. */
export const saveQuoteLines = bsb.action(
  {
    input: v.object({
      quoteId: Id,
      currency: Currency,
      lines: v.pipe(v.array(QuoteLine), v.maxLength(100)),
    }),
    requireTenant: true,
    permission: "quotes.write",
  },
  async ({ quoteId, currency, lines }, { db, auth }) => {
    const saved = await db.quotes.setLines(
      quoteId,
      lines.map((line) => ({
        description: line.description,
        quantity: line.quantity,
        unitAmount: parseMoney(line.unitAmount, currency),
        discountBps: Math.round(line.discountPercent * 100),
        taxRateBps: Math.round(line.taxPercent * 100),
      })),
    );

    if (!saved.ok) {
      return saved;
    }

    await refreshCaller(auth);

    return ok(saved.data.total);
  },
);

/** Sends a draft for acceptance. */
export const sendQuote = bsb.action(
  {
    input: v.object({ quoteId: Id }),
    requireTenant: true,
    permission: "quotes.write",
  },
  async ({ quoteId }, { db, auth }) => {
    const sent = await db.quotes.send(quoteId);

    if (!sent.ok) {
      return sent;
    }

    await refreshCaller(auth);

    return ok(true);
  },
);

/** Records the customer's answer, taken by phone or email. */
export const decideQuote = bsb.action(
  {
    input: v.object({
      quoteId: Id,
      decision: v.picklist(["accepted", "rejected", "changes_requested"]),
    }),
    requireTenant: true,
    permission: "quotes.write",
  },
  async ({ quoteId, decision }, { db, auth }) => {
    const decided = await db.quotes.decide(quoteId, decision);

    if (!decided.ok) {
      return decided;
    }

    await refreshCaller(auth);

    return ok(true);
  },
);

/** Starts a new draft revision and returns its id. */
export const reviseQuote = bsb.action(
  {
    input: v.object({ quoteId: Id }),
    requireTenant: true,
    permission: "quotes.write",
  },
  async ({ quoteId }, { db, auth }) => {
    const revised = await db.quotes.revise(quoteId);

    if (!revised.ok) {
      return revised;
    }

    await refreshCaller(auth);

    return ok({ id: revised.data.id });
  },
);
