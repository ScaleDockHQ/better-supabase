"use server";

import { ok } from "better-supabase";
import { parseMoney } from "better-supabase/commerce";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import { CRM_TAG } from "@/features/crm/crm-cache";
import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { SALES_TAG } from "./sales-cache";

const Id = v.pipe(v.string(), v.uuid());
const Name = v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200));
const IsoDate = v.pipe(v.string(), v.isoDate());
const Currency = v.picklist(["EUR", "USD", "GBP"]);
const Decimal = v.pipe(v.string(), v.trim(), v.regex(/^\d+(\.\d{1,2})?$/u));

/** An empty form field is `""`; it means "not given". */
const Optional = v.pipe(
  v.optional(v.string(), ""),
  v.trim(),
  v.maxLength(2000),
  v.transform((value) => (value === "" ? undefined : value)),
);

/** A whole number a form sends as text and a button sends as a number. */
const Whole = (min: number, max: number) =>
  v.pipe(
    v.union([v.string(), v.number()]),
    v.transform(Number),
    v.integer(),
    v.minValue(min),
    v.maxValue(max),
  );

const TAGS = [SALES_TAG, CRM_TAG];

/**
 * `{ [key]: value }` when a value is given, `{}` otherwise, for exact optional
 * properties.
 */
function given<K extends string, V>(
  key: K,
  value: V | undefined,
): { readonly [P in K]?: V } {
  // SAFETY: the object holds the key only when `value` is defined.
  return (value === undefined ? {} : { [key]: value }) as {
    readonly [P in K]?: V;
  };
}

/** Closes a deal as won. */
export const winDeal = bsb.action(
  {
    input: v.object({ dealId: Id, note: Optional }),
    requireTenant: true,
    permission: "deals.write",
  },
  async ({ dealId, note }, { db, auth }) => {
    const won = await db.deals.win({ dealId, note });

    if (!won.ok) {
      return won;
    }

    await refreshCaller(auth, TAGS);

    return ok(true);
  },
);

/** Closes a deal as lost, with an optional reason. */
export const loseDeal = bsb.action(
  {
    input: v.object({ dealId: Id, reason: Optional }),
    requireTenant: true,
    permission: "deals.write",
  },
  async ({ dealId, reason }, { db, auth }) => {
    const lost = await db.deals.lose({ dealId, reason });

    if (!lost.ok) {
      return lost;
    }

    await refreshCaller(auth, TAGS);

    return ok(true);
  },
);

/** Opens a closed deal again in the first open stage. */
export const reopenDeal = bsb.action(
  {
    input: v.object({ dealId: Id }),
    requireTenant: true,
    permission: "deals.write",
  },
  async ({ dealId }, { db, auth }) => {
    const reopened = await db.deals.reopen({ dealId });

    if (!reopened.ok) {
      return reopened;
    }

    await refreshCaller(auth, TAGS);

    return ok(true);
  },
);

/** Snapshots the forecast of a period, so a later review compares weeks. */
export const takeForecastSnapshot = bsb.action(
  {
    input: v.object({
      since: IsoDate,
      until: IsoDate,
      currency: Currency,
      target: Optional,
    }),
    requireTenant: true,
    permission: "forecasts.snapshot",
  },
  async ({ since, until, currency, target }, { tenant, db, auth }) => {
    const snapshot = await db.forecasts.snapshot({
      organizationId: tenant,
      period: {
        since: Temporal.PlainDate.from(since),
        until: Temporal.PlainDate.from(until),
        currency,
        ...given(
          "target",
          target !== undefined && v.is(Decimal, target)
            ? parseMoney(target, currency)
            : undefined,
        ),
      },
    });

    if (!snapshot.ok) {
      return snapshot;
    }

    await refreshCaller(auth, TAGS);

    return ok({ id: snapshot.data.id });
  },
);

const LIFECYCLES = [
  "lead",
  "mql",
  "sql",
  "opportunity",
  "customer",
  "churned",
] as const;

/** Saves a segment of companies in one lifecycle stage. */
export const createSegment = bsb.action(
  {
    input: v.object({
      name: Name,
      description: Optional,
      lifecycle: v.picklist(LIFECYCLES),
    }),
    requireTenant: true,
    permission: "segments.write",
  },
  async ({ name, description, lifecycle }, { tenant, db, auth }) => {
    const saved = await db.segments.upsert({
      organizationId: tenant,
      segment: {
        name,
        description: description ?? null,
        subjectType: "company",
        conditions: {
          id: "root",
          type: "group",
          combinator: "and",
          rules: [
            {
              id: "lifecycle",
              type: "rule",
              path: ["lifecycle"],
              operator: "is",
              value: lifecycle,
            },
          ],
        },
      },
    });

    if (!saved.ok) {
      return saved;
    }

    await refreshCaller(auth, TAGS);

    return ok({ id: saved.data.id });
  },
);

/** Evaluates a segment now and stores who entered and left. */
export const refreshSegment = bsb.action(
  {
    input: v.object({ segmentId: Id }),
    requireTenant: true,
    permission: "segments.write",
  },
  async ({ segmentId }, { db, auth }) => {
    const refreshed = await db.segments.refresh(segmentId);

    if (!refreshed.ok) {
      return refreshed;
    }

    await refreshCaller(auth, TAGS);

    return ok(refreshed.data);
  },
);

export const deleteSegment = bsb.action(
  {
    input: v.object({ segmentId: Id }),
    requireTenant: true,
    permission: "segments.write",
  },
  async ({ segmentId }, { db, auth }) => {
    const removed = await db.segments.remove(segmentId);

    if (!removed.ok) {
      return removed;
    }

    await refreshCaller(auth, TAGS);

    return ok(removed.data);
  },
);

/** Creates a queue that picks an owner for new companies. */
export const createQueue = bsb.action(
  {
    input: v.object({
      name: Name,
      subjectType: v.picklist(["company", "person", "deal"]),
      strategy: v.picklist(["round_robin", "weighted"]),
    }),
    requireTenant: true,
    permission: "assignment.manage",
  },
  async ({ name, subjectType, strategy }, { tenant, db, auth }) => {
    const saved = await db.assignment.saveQueue({
      organizationId: tenant,
      queue: { name, subjectType, strategy },
    });

    if (!saved.ok) {
      return saved;
    }

    await refreshCaller(auth, TAGS);

    return ok({ id: saved.data.id });
  },
);

/** Replaces a queue's members, each with a weight and an active flag. */
export const setQueueMembers = bsb.action(
  {
    input: v.object({
      queueId: Id,
      members: v.array(
        v.object({ userId: Id, weight: Whole(1, 100), active: v.boolean() }),
      ),
    }),
    requireTenant: true,
    permission: "assignment.manage",
  },
  async ({ queueId, members }, { db, auth }) => {
    const saved = await db.assignment.setMembers({ queueId, members });

    if (!saved.ok) {
      return saved;
    }

    await refreshCaller(auth, TAGS);

    return ok(true);
  },
);

export const setQueueEnabled = bsb.action(
  {
    input: v.object({ queueId: Id, enabled: v.boolean() }),
    requireTenant: true,
    permission: "assignment.manage",
  },
  async ({ queueId, enabled }, { tenant, db, auth }) => {
    const saved = await db.assignment.saveQueue({
      organizationId: tenant,
      queue: { id: queueId, enabled },
    });

    if (!saved.ok) {
      return saved;
    }

    await refreshCaller(auth, TAGS);

    return ok(true);
  },
);

/** Creates a score model that gives points to companies in one lifecycle stage. */
export const createScoreModel = bsb.action(
  {
    input: v.object({
      key: v.pipe(v.string(), v.trim(), v.regex(/^[a-z][a-z0-9_]{1,30}$/u)),
      name: Name,
      lifecycle: v.picklist(LIFECYCLES),
      points: Whole(1, 100),
    }),
    requireTenant: true,
    permission: "scores.manage",
  },
  async ({ key, name, lifecycle, points }, { db, auth }) => {
    const saved = await db.scores.saveModel({
      key,
      name,
      subjectType: "company",
      rules: [
        {
          id: lifecycle,
          label: lifecycle,
          points,
          conditions: {
            id: "root",
            type: "group",
            combinator: "and",
            rules: [
              {
                id: "r1",
                type: "rule",
                path: ["lifecycle"],
                operator: "is",
                value: lifecycle,
              },
            ],
          },
        },
      ],
      bands: [
        { label: "cold", min: 0 },
        { label: "warm", min: Math.max(1, Math.ceil(points / 2)) },
        { label: "hot", min: points },
      ],
    });

    if (!saved.ok) {
      return saved;
    }

    await refreshCaller(auth, TAGS);

    return ok({ id: saved.data.id });
  },
);

export const setScoreModelEnabled = bsb.action(
  {
    input: v.object({ modelId: Id, enabled: v.boolean() }),
    requireTenant: true,
    permission: "scores.manage",
  },
  async ({ modelId, enabled }, { db, auth }) => {
    const saved = await db.scores.saveModel({ id: modelId, enabled });

    if (!saved.ok) {
      return saved;
    }

    await refreshCaller(auth, TAGS);

    return ok(true);
  },
);

/** Scores one company or person with the lead model and saves the result. */
export const scoreRecord = bsb.action(
  {
    input: v.object({
      subjectType: v.picklist(["company", "person"]),
      subjectId: Id,
    }),
    requireTenant: true,
    permission: "scores.compute",
  },
  async ({ subjectType, subjectId }, { db, auth }) => {
    const scored = await db.leadScoring.score({
      type: subjectType,
      id: subjectId,
    });

    if (!scored.ok) {
      return scored;
    }

    await refreshCaller(auth, TAGS);

    return ok({ score: scored.data.score, band: scored.data.band ?? null });
  },
);

/** Drafts a contract. */
export const createContract = bsb.action(
  {
    input: v.object({
      title: Name,
      value: Optional,
      currency: Currency,
      startsOn: Optional,
      endsOn: Optional,
      autoRenew: v.pipe(
        v.optional(v.picklist(["yes", "no"]), "no"),
        v.transform((value) => value === "yes"),
      ),
    }),
    requireTenant: true,
    permission: "contracts.write",
  },
  async (
    { title, value, currency, startsOn, endsOn, autoRenew },
    { tenant, db, auth },
  ) => {
    const created = await db.contracts.create({
      organizationId: tenant,
      input: {
        title,
        autoRenew,
        ...given(
          "value",
          value !== undefined && v.is(Decimal, value)
            ? parseMoney(value, currency)
            : undefined,
        ),
        ...given(
          "startsOn",
          startsOn !== undefined && v.is(IsoDate, startsOn)
            ? Temporal.PlainDate.from(startsOn)
            : undefined,
        ),
        ...given(
          "endsOn",
          endsOn !== undefined && v.is(IsoDate, endsOn)
            ? Temporal.PlainDate.from(endsOn)
            : undefined,
        ),
      },
    });

    if (!created.ok) {
      return created;
    }

    await refreshCaller(auth, TAGS);

    return ok({ id: created.data.id });
  },
);

/** Moves a contract through review, activation and termination. */
export const transitionContract = bsb.action(
  {
    input: v.object({
      contractId: Id,
      action: v.picklist([
        "submit",
        "return",
        "activate",
        "recall",
        "terminate",
      ]),
      reason: Optional,
    }),
    requireTenant: true,
    permission: "contracts.write",
  },
  async ({ contractId, action, reason }, { db, auth }) => {
    const moved = await db.contracts.transition({ contractId, action, reason });

    if (!moved.ok) {
      return moved;
    }

    await refreshCaller(auth, TAGS);

    return ok(true);
  },
);

export const addObligation = bsb.action(
  {
    input: v.object({ contractId: Id, title: Name, dueOn: Optional }),
    requireTenant: true,
    permission: "contracts.write",
  },
  async ({ contractId, title, dueOn }, { db, auth }) => {
    const saved = await db.contracts.saveObligation({
      contractId,
      input: {
        title,
        ...given(
          "dueOn",
          dueOn !== undefined && v.is(IsoDate, dueOn)
            ? Temporal.PlainDate.from(dueOn)
            : undefined,
        ),
      },
    });

    if (!saved.ok) {
      return saved;
    }

    await refreshCaller(auth, TAGS);

    return ok(true);
  },
);

export const setObligationStatus = bsb.action(
  {
    input: v.object({
      obligationId: Id,
      status: v.picklist(["open", "done", "waived"]),
    }),
    requireTenant: true,
    permission: "contracts.write",
  },
  async ({ obligationId, status }, { db, auth }) => {
    const saved = await db.contracts.setObligationStatus({
      obligationId,
      status,
    });

    if (!saved.ok) {
      return saved;
    }

    await refreshCaller(auth, TAGS);

    return ok(true);
  },
);

/** A flat-rate commission plan, in basis points of the sale. */
export const createCommissionPlan = bsb.action(
  {
    input: v.object({
      name: Name,
      rate: v.pipe(v.string(), v.trim(), v.regex(/^\d{1,2}(\.\d{1,2})?$/u)),
    }),
    requireTenant: true,
    permission: "commissions.manage",
  },
  async ({ name, rate }, { db, auth }) => {
    const saved = await db.commissions.savePlan({
      name,
      kind: "flat",
      rateBps: Math.round(Number(rate) * 100),
    });

    if (!saved.ok) {
      return saved;
    }

    await refreshCaller(auth, TAGS);

    return ok({ id: saved.data.id });
  },
);

/** Builds a seller's statement for a period from their accrued commissions. */
export const buildCommissionStatement = bsb.action(
  {
    input: v.object({
      sellerId: Id,
      currency: Currency,
      startsOn: IsoDate,
      endsOn: IsoDate,
    }),
    requireTenant: true,
    permission: "commissions.manage",
  },
  async ({ sellerId, currency, startsOn, endsOn }, { db, auth }) => {
    const built = await db.commissions.buildStatement({
      sellerId,
      currency,
      startsOn: Temporal.PlainDate.from(startsOn),
      endsOn: Temporal.PlainDate.from(endsOn),
    });

    if (!built.ok) {
      return built;
    }

    await refreshCaller(auth, TAGS);

    return ok({ id: built.data.id });
  },
);

/** Finalizes an open statement, or pays a finalized one on the ledger. */
export const advanceStatement = bsb.action(
  {
    input: v.object({ statementId: Id, step: v.picklist(["finalize", "pay"]) }),
    requireTenant: true,
    permission: "commissions.manage",
  },
  async ({ statementId, step }, { db, auth }) => {
    const advanced =
      step === "finalize"
        ? await db.commissions.finalizeStatement(statementId)
        : await db.commissions.payStatement(statementId);

    if (!advanced.ok) {
      return advanced;
    }

    await refreshCaller(auth, TAGS);

    return ok(true);
  },
);

/** Creates a referral code for the caller. */
export const createReferralCode = bsb.action(
  {
    input: v.object({
      maxUses: v.pipe(
        v.optional(v.string(), ""),
        v.trim(),
        v.transform((value) => (value === "" ? undefined : Number(value))),
        v.check(
          (value) =>
            value === undefined ||
            (Number.isInteger(value) && value >= 1 && value <= 10_000),
        ),
      ),
    }),
    requireTenant: true,
    permission: "referrals.write",
  },
  async ({ maxUses }, { db, auth }) => {
    const created = await db.referrals.createCode(
      maxUses === undefined ? {} : { maxUses },
    );

    if (!created.ok) {
      return created;
    }

    await refreshCaller(auth, TAGS);

    return ok({ code: created.data.code });
  },
);

/** Sets the owner of up to 100 deals; a refused deal does not stop the others. */
export const assignDealOwners = bsb.action(
  {
    input: v.object({
      ownerId: Id,
      dealIds: v.pipe(
        v.string(),
        v.transform((value) => value.split(",")),
        v.array(Id),
        v.minLength(1),
        v.maxLength(100),
      ),
    }),
    requireTenant: true,
    permission: "deals.write",
  },
  async ({ ownerId, dealIds }, { db, auth }) => {
    const changed = await db.deals.update({
      changes: dealIds.map((dealId) => ({
        dealId,
        field: "ownerId",
        value: ownerId,
      })),
    });

    if (!changed.ok) {
      return changed;
    }

    await refreshCaller(auth, TAGS);

    return ok({
      assigned: new Set(changed.data.accepted.map((entry) => entry.dealId))
        .size,
      refused: new Set(changed.data.rejected.map((entry) => entry.dealId)).size,
    });
  },
);
