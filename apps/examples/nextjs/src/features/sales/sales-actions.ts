"use server";

import { ok } from "better-supabase";
import { parseMoney } from "better-supabase/commerce";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

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

const TAGS = [tags.sales(), tags.crm()];

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
export const winDeal = bsb.blockAction(
  ({ db }) => db.deals,
  "win",
  {
    input: v.object({ dealId: Id, note: Optional }),
    requireTenant: true,
    permission: "deals.write",
    tags: () => TAGS,
    refresh: true,
  },
  () => true,
);

/** Opens a closed deal again in the first open stage. */
export const reopenDeal = bsb.blockAction(
  ({ db }) => db.deals,
  "reopen",
  {
    input: v.object({ dealId: Id }),
    requireTenant: true,
    permission: "deals.write",
    tags: () => TAGS,
    refresh: true,
  },
  () => true,
);

/** Snapshots the forecast of a period, so a later review compares weeks. */
export const takeForecastSnapshot = bsb.blockAction(
  ({ db }) => db.forecasts,
  "snapshot",
  {
    input: v.object({
      since: IsoDate,
      until: IsoDate,
      currency: Currency,
      target: Optional,
    }),
    requireTenant: true,
    permission: "forecasts.snapshot",
    tags: () => TAGS,
    refresh: true,
    args: ({ since, until, currency, target }, { tenant }) => [
      {
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
      },
    ],
  },
  (snapshot) => ({ id: snapshot.id }),
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
export const createSegment = bsb.blockAction(
  ({ db }) => db.segments,
  "upsert",
  {
    input: v.object({
      name: Name,
      description: Optional,
      lifecycle: v.picklist(LIFECYCLES),
    }),
    requireTenant: true,
    permission: "segments.write",
    tags: () => TAGS,
    refresh: true,
    args: ({ name, description, lifecycle }, { tenant }) => [
      {
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
      },
    ],
  },
  (saved) => ({ id: saved.id }),
);

/** Evaluates a segment now and stores who entered and left. */
export const refreshSegment = bsb.blockAction(
  ({ db }) => db.segments,
  "refresh",
  {
    input: v.object({ segmentId: Id }),
    requireTenant: true,
    permission: "segments.write",
    tags: () => TAGS,
    refresh: true,
    args: ({ segmentId }) => [segmentId],
  },
);

export const deleteSegment = bsb.blockAction(
  ({ db }) => db.segments,
  "remove",
  {
    input: v.object({ segmentId: Id }),
    requireTenant: true,
    permission: "segments.write",
    tags: () => TAGS,
    refresh: true,
    args: ({ segmentId }) => [segmentId],
  },
);

/** Creates a queue that picks an owner for new companies. */
export const createQueue = bsb.blockAction(
  ({ db }) => db.assignment,
  "saveQueue",
  {
    input: v.object({
      name: Name,
      subjectType: v.picklist(["company", "person", "deal"]),
      strategy: v.picklist(["round_robin", "weighted"]),
    }),
    requireTenant: true,
    permission: "assignment.manage",
    tags: () => TAGS,
    refresh: true,
    args: ({ name, subjectType, strategy }, { tenant }) => [
      { organizationId: tenant, queue: { name, subjectType, strategy } },
    ],
  },
  (saved) => ({ id: saved.id }),
);

/** Replaces a queue's members, each with a weight and an active flag. */
export const setQueueMembers = bsb.blockAction(
  ({ db }) => db.assignment,
  "setMembers",
  {
    input: v.object({
      queueId: Id,
      members: v.array(
        v.object({ userId: Id, weight: Whole(1, 100), active: v.boolean() }),
      ),
    }),
    requireTenant: true,
    permission: "assignment.manage",
    tags: () => TAGS,
    refresh: true,
  },
  () => true,
);

export const setQueueEnabled = bsb.blockAction(
  ({ db }) => db.assignment,
  "saveQueue",
  {
    input: v.object({ queueId: Id, enabled: v.boolean() }),
    requireTenant: true,
    permission: "assignment.manage",
    tags: () => TAGS,
    refresh: true,
    args: ({ queueId, enabled }, { tenant }) => [
      { organizationId: tenant, queue: { id: queueId, enabled } },
    ],
  },
  () => true,
);

/** Creates a score model that gives points to companies in one lifecycle stage. */
export const createScoreModel = bsb.blockAction(
  ({ db }) => db.scores,
  "saveModel",
  {
    input: v.object({
      key: v.pipe(v.string(), v.trim(), v.regex(/^[a-z][a-z0-9_]{1,30}$/u)),
      name: Name,
      lifecycle: v.picklist(LIFECYCLES),
      points: Whole(1, 100),
    }),
    requireTenant: true,
    permission: "scores.manage",
    tags: () => TAGS,
    refresh: true,
    args: ({ key, name, lifecycle, points }) => [
      {
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
      },
    ],
  },
  (saved) => ({ id: saved.id }),
);

export const setScoreModelEnabled = bsb.blockAction(
  ({ db }) => db.scores,
  "saveModel",
  {
    input: v.object({ modelId: Id, enabled: v.boolean() }),
    requireTenant: true,
    permission: "scores.manage",
    tags: () => TAGS,
    refresh: true,
    args: ({ modelId, enabled }) => [{ id: modelId, enabled }],
  },
  () => true,
);

/** Scores one company or person with the lead model and saves the result. */
export const scoreRecord = bsb.blockAction(
  ({ db }) => db.leadScoring,
  "score",
  {
    input: v.object({
      subjectType: v.picklist(["company", "person"]),
      subjectId: Id,
    }),
    requireTenant: true,
    permission: "scores.compute",
    tags: () => TAGS,
    refresh: true,
    args: ({ subjectType, subjectId }) => [
      { type: subjectType, id: subjectId },
    ],
  },
  (scored) => ({ score: scored.score, band: scored.band ?? null }),
);

/** Drafts a contract. */
export const createContract = bsb.blockAction(
  ({ db }) => db.contracts,
  "create",
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
    tags: () => TAGS,
    refresh: true,
    args: (
      { title, value, currency, startsOn, endsOn, autoRenew },
      { tenant },
    ) => [
      {
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
      },
    ],
  },
  (created) => ({ id: created.id }),
);

/** Moves a contract through review, activation and termination. */
export const transitionContract = bsb.blockAction(
  ({ db }) => db.contracts,
  "transition",
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
    tags: () => TAGS,
    refresh: true,
  },
  () => true,
);

export const addObligation = bsb.blockAction(
  ({ db }) => db.contracts,
  "saveObligation",
  {
    input: v.object({ contractId: Id, title: Name, dueOn: Optional }),
    requireTenant: true,
    permission: "contracts.write",
    tags: () => TAGS,
    refresh: true,
    args: ({ contractId, title, dueOn }) => [
      {
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
      },
    ],
  },
  () => true,
);

export const setObligationStatus = bsb.blockAction(
  ({ db }) => db.contracts,
  "setObligationStatus",
  {
    input: v.object({
      obligationId: Id,
      status: v.picklist(["open", "done", "waived"]),
    }),
    requireTenant: true,
    permission: "contracts.write",
    tags: () => TAGS,
    refresh: true,
  },
  () => true,
);

/** A flat-rate commission plan, in basis points of the sale. */
export const createCommissionPlan = bsb.blockAction(
  ({ db }) => db.commissions,
  "savePlan",
  {
    input: v.object({
      name: Name,
      rate: v.pipe(v.string(), v.trim(), v.regex(/^\d{1,2}(\.\d{1,2})?$/u)),
    }),
    requireTenant: true,
    permission: "commissions.manage",
    tags: () => TAGS,
    refresh: true,
    args: ({ name, rate }) => [
      { name, kind: "flat", rateBps: Math.round(Number(rate) * 100) },
    ],
  },
  (saved) => ({ id: saved.id }),
);

/** Builds a seller's statement for a period from their accrued commissions. */
export const buildCommissionStatement = bsb.blockAction(
  ({ db }) => db.commissions,
  "buildStatement",
  {
    input: v.object({
      sellerId: Id,
      currency: Currency,
      startsOn: IsoDate,
      endsOn: IsoDate,
    }),
    requireTenant: true,
    permission: "commissions.manage",
    tags: () => TAGS,
    refresh: true,
    args: ({ sellerId, currency, startsOn, endsOn }) => [
      {
        sellerId,
        currency,
        startsOn: Temporal.PlainDate.from(startsOn),
        endsOn: Temporal.PlainDate.from(endsOn),
      },
    ],
  },
  (built) => ({ id: built.id }),
);

/** Finalizes an open statement, or pays a finalized one on the ledger. */
export const advanceStatement = bsb.action(
  {
    input: v.object({ statementId: Id, step: v.picklist(["finalize", "pay"]) }),
    requireTenant: true,
    permission: "commissions.manage",
    tags: () => TAGS,
    refresh: true,
  },
  async ({ statementId, step }, { db }) => {
    const advanced =
      step === "finalize"
        ? await db.commissions.finalizeStatement(statementId)
        : await db.commissions.payStatement(statementId);

    if (!advanced.ok) {
      return advanced;
    }

    return ok(true);
  },
);

/** Creates a referral code for the caller. */
export const createReferralCode = bsb.blockAction(
  ({ db }) => db.referrals,
  "createCode",
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
    tags: () => TAGS,
    refresh: true,
    args: ({ maxUses }) => [maxUses === undefined ? {} : { maxUses }],
  },
  (created) => ({ code: created.code }),
);

/** Sets the owner of up to 100 deals; a refused deal does not stop the others. */
export const assignDealOwners = bsb.blockAction(
  ({ db }) => db.deals,
  "update",
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
    tags: () => TAGS,
    refresh: true,
    args: ({ ownerId, dealIds }) => [
      {
        changes: dealIds.map((dealId) => ({
          dealId,
          field: "ownerId",
          value: ownerId,
        })),
      },
    ],
  },
  (changed) => ({
    assigned: new Set(changed.accepted.map((entry) => entry.dealId)).size,
    refused: new Set(changed.rejected.map((entry) => entry.dealId)).size,
  }),
);
