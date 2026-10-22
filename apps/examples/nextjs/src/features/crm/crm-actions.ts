"use server";

import { dbError, err, ok } from "better-supabase";
import { parseMoney } from "better-supabase/commerce";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import { can } from "@/features/user/user-permissions";
import { blocks } from "@/lib/blocks";
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
    authorize: (session) => can(session, "parties.write"),
  },
  async ({ kind, name, email, domain }, { tenant, supabase, auth }) => {
    const { parties } = blocks(supabase);

    const saved =
      kind === "company"
        ? await parties.saveCompany(tenant, { name, domain: domain ?? null })
        : await parties.savePerson(tenant, { name, email: email ?? null });

    if (!saved.ok) {
      return saved;
    }

    refreshCaller(auth);

    return ok({ id: saved.data.id, name: saved.data.name });
  },
);

/** Adds a person to a company, with an optional role. */
export const linkPerson = bsb.action(
  {
    input: v.object({ companyId: Id, personId: Id, role: Optional }),
    requireTenant: true,
    authorize: (session) => can(session, "parties.write"),
  },
  async ({ companyId, personId, role }, { supabase, auth }) => {
    const linked = await blocks(supabase).parties.linkPerson(
      companyId,
      personId,
      role ? { role } : {},
    );

    if (!linked.ok) {
      return linked;
    }

    refreshCaller(auth);

    return ok(true);
  },
);

/** Logs a call, email, meeting or note on a contact. */
export const logActivity = bsb.action(
  {
    input: v.object({
      subjectType: v.picklist(["company", "person"]),
      subjectId: Id,
      type: v.picklist(["call", "email", "meeting", "note"]),
      title: Name,
      body: Optional,
    }),
    requireTenant: true,
    authorize: (session) => can(session, "engagements.write"),
  },
  async (
    { subjectType, subjectId, type, title, body },
    { tenant, supabase, auth },
  ) => {
    const logged = await blocks(supabase).engagements.log(
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

    refreshCaller(auth);

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
  {
    requireTenant: true,
    authorize: (session) => can(session, "pipelines.manage"),
  },
  async (_input, { tenant, supabase, auth }) => {
    const { pipelines } = blocks(supabase);
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

    refreshCaller(auth);

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
    authorize: (session) => can(session, "deals.write"),
  },
  async (
    { name, amount, currency, closeOn, pipelineId, stageId },
    { tenant, supabase, auth },
  ) => {
    const created = await blocks(supabase).deals.create(tenant, {
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

    refreshCaller(auth);

    return ok({ id: created.data.id, identifier: created.data.identifier });
  },
);

/** Moves a deal to another stage; the deals block checks the transition. */
export const moveDeal = bsb.action(
  {
    input: v.object({ dealId: Id, stageId: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "deals.write"),
  },
  async ({ dealId, stageId }, { supabase, auth }) => {
    const moved = await blocks(supabase).deals.update([
      { dealId, field: "stageId", value: stageId },
    ]);

    if (!moved.ok) {
      return moved;
    }

    const [rejected] = moved.data.rejected;

    if (rejected) {
      return err(dbError("raised", rejected.reason));
    }

    refreshCaller(auth);

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
    authorize: (session) => can(session, "targets.manage"),
  },
  async (
    { name, metric, goal, currency, periodStart, periodEnd },
    { tenant, supabase, auth },
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

    const saved = await blocks(supabase).targets.upsert(
      tenant,
      amount
        ? { ...target, goal: parseMoney(goal, currency).amount, currency }
        : { ...target, goal: BigInt(goal) },
    );

    if (!saved.ok) {
      return saved;
    }

    refreshCaller(auth);

    return ok({ id: saved.data.id });
  },
);

/** Creates an empty draft quote; the builder adds its lines. */
export const createQuote = bsb.action(
  {
    input: v.object({ title: Name, currency: Currency }),
    requireTenant: true,
    authorize: (session) => can(session, "quotes.write"),
  },
  async ({ title, currency }, { tenant, supabase, auth }) => {
    const created = await blocks(supabase).quotes.create(tenant, {
      title,
      currency,
    });

    if (!created.ok) {
      return created;
    }

    refreshCaller(auth);

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
    authorize: (session) => can(session, "quotes.write"),
  },
  async ({ quoteId, currency, lines }, { supabase, auth }) => {
    const saved = await blocks(supabase).quotes.setLines(
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

    refreshCaller(auth);

    return ok(saved.data.total);
  },
);

/** Sends a draft for acceptance. */
export const sendQuote = bsb.action(
  {
    input: v.object({ quoteId: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "quotes.write"),
  },
  async ({ quoteId }, { supabase, auth }) => {
    const sent = await blocks(supabase).quotes.send(quoteId);

    if (!sent.ok) {
      return sent;
    }

    refreshCaller(auth);

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
    authorize: (session) => can(session, "quotes.write"),
  },
  async ({ quoteId, decision }, { supabase, auth }) => {
    const decided = await blocks(supabase).quotes.decide(quoteId, decision);

    if (!decided.ok) {
      return decided;
    }

    refreshCaller(auth);

    return ok(true);
  },
);

/** Starts a new draft revision and returns its id. */
export const reviseQuote = bsb.action(
  {
    input: v.object({ quoteId: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "quotes.write"),
  },
  async ({ quoteId }, { supabase, auth }) => {
    const revised = await blocks(supabase).quotes.revise(quoteId);

    if (!revised.ok) {
      return revised;
    }

    refreshCaller(auth);

    return ok({ id: revised.data.id });
  },
);
