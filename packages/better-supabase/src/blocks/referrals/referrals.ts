import type {
  Count,
  FacetResult,
  ListPage,
  PageOptions,
} from "../../core/block-helpers.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { CountOptions, FacetOptions } from "../../core/entity-list.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult as AsyncResultType } from "../../core/result.ts";
import type { BlockOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { entityList } from "../../core/entity-list.ts";
import { temporal } from "../../core/temporal-required.ts";
import { REFERRAL_STATUSES } from "../../sql/modules/referrals-values.ts";
import {
  applyTemporal,
  bigintOf,
  blockCall,
  enumOrThrow,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";
import { referralCodeListSurface, referralListSurface } from "./lists.ts";

/** Where a referral stands: attributed at signup, qualified, then rewarded. */
export type ReferralStatus = (typeof REFERRAL_STATUSES)[number];

/** The reward a referral earns: an amount of a ledger unit. */
export interface ReferralReward {
  /** In the unit's smallest amount. */
  readonly amount: bigint;
  /** The ledger unit, such as `EUR` or `points`. */
  readonly unit: string;
}

export interface ReferralCode {
  readonly id: string;
  readonly organizationId: string;
  readonly code: string;
  readonly referrerId: string;
  readonly invitationId?: string;
  readonly reward?: ReferralReward;
  readonly maxUses?: number;
  readonly uses: number;
  readonly active: boolean;
  readonly expiresAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
}

export interface Referral {
  readonly id: string;
  readonly organizationId: string;
  readonly codeId: string;
  readonly referrerId: string;
  readonly referredUserId?: string;
  readonly referredOrganizationId?: string;
  readonly referredEmail?: string;
  readonly status: ReferralStatus;
  /** What the code promised when the referral was attributed. */
  readonly reward?: ReferralReward;
  readonly qualifiedAt?: Temporal.Instant;
  readonly rewardedAt?: Temporal.Instant;
  readonly ledgerTransactionId?: string;
  readonly createdAt: Temporal.Instant;
}

export interface CreateReferralCodeInput {
  /** The member who shares the code. The caller by default. */
  readonly referrerId?: string;
  /** Four to 32 letters or digits. Generated when omitted. */
  readonly code?: string;
  /** Attributes the referral when this invitation is accepted. */
  readonly invitationId?: string;
  readonly reward?: ReferralReward;
  readonly maxUses?: number;
  readonly expiresAt?: Temporal.Instant;
}

export interface AttributeReferralInput {
  readonly code: string;
  readonly referredUserId?: string;
  readonly referredOrganizationId?: string;
  readonly referredEmail?: string;
}

export interface ReferralListOptions {
  readonly referrerId?: string;
  readonly status?: ReferralStatus;
  /** At most 500; 100 by default. */
  readonly limit?: number;
}

export interface ReferralsOptions extends BlockOptions {
  readonly hooks?: BlockHooks<Referrals>;
  readonly logger?: Logger;
}

export interface Referrals {
  createCode(input?: CreateReferralCodeInput): AsyncResultType<ReferralCode>;
  /**
   * Attributes the user or organization that signed up with a code. Calling it
   * again for the same user or organization returns the first referral.
   */
  attribute(input: AttributeReferralInput): AsyncResultType<Referral>;
  /**
   * Marks the referral of a user or organization as qualified after the event
   * that earns the reward, and posts the reward to the ledger once. Resolves to
   * `undefined` when nothing referred them.
   */
  qualify(input: {
    readonly referredUserId?: string;
    readonly referredOrganizationId?: string;
    /** What qualified it, such as `invoices/inv_1`. */
    readonly source?: string;
  }): AsyncResultType<Referral | undefined>;
  /** Voids a referral and reverses a reward already posted. */
  void(input: {
    readonly referralId: string;
    readonly reason?: string;
  }): AsyncResultType<Referral>;
  listCodes(list?: {
    readonly referrerId?: string;
    readonly limit?: number;
  }): AsyncResultType<readonly ReferralCode[]>;
  listReferrals(
    list?: ReferralListOptions,
  ): AsyncResultType<readonly Referral[]>;
  /**
   * One keyset page of referrals, newest first or by `sort`, with `hasMore` and
   * a `nextCursor`.
   */
  referralPage(options?: PageOptions): AsyncResultType<ListPage<Referral>>;
  /**
   * The values of each facet of referrals and their counts, under the page's
   * filters.
   */
  referralFacets(
    options?: FacetOptions,
  ): AsyncResultType<readonly FacetResult[]>;
  /** How many of referrals match the page's filters. */
  referralCount(options?: CountOptions): AsyncResultType<Count>;
  /**
   * One keyset page of referral codes, newest first or by `sort`, with
   * `hasMore` and a `nextCursor`.
   */
  codePage(options?: PageOptions): AsyncResultType<ListPage<ReferralCode>>;
  /**
   * The values of each facet of referral codes and their counts, under the
   * page's filters.
   */
  codeFacets(options?: FacetOptions): AsyncResultType<readonly FacetResult[]>;
  /** How many of referral codes match the page's filters. */
  codeCount(options?: CountOptions): AsyncResultType<Count>;
}

function rewardOf(amount: unknown, unit: unknown): ReferralReward | undefined {
  const value = bigintOf(amount, "rewardAmount");

  return value > 0n && typeof unit === "string"
    ? { amount: value, unit }
    : undefined;
}

function codeOf(value: unknown, fn: string): ReferralCode {
  const row = recordOf(value, fn);
  const reward = rewardOf(row["rewardAmount"], row["rewardUnit"]);
  const invitationId = optionalText(row["invitationId"]);
  const expiresAt = optionalInstant(row["expiresAt"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    code: textOf(row["code"]),
    referrerId: textOf(row["referrerId"]),
    uses: Number(row["uses"]),
    active: row["active"] === true,
    createdAt: temporal().Instant.from(textOf(row["createdAt"])),
    ...(invitationId === undefined ? {} : { invitationId }),
    ...(reward === undefined ? {} : { reward }),
    ...(typeof row["maxUses"] === "number" ? { maxUses: row["maxUses"] } : {}),
    ...(expiresAt === undefined ? {} : { expiresAt }),
  };
}

function referralOf(value: unknown, fn: string): Referral {
  const row = recordOf(value, fn);
  const reward = rewardOf(row["rewardAmount"], row["rewardUnit"]);
  const referredUserId = optionalText(row["referredUserId"]);
  const referredOrganizationId = optionalText(row["referredOrganizationId"]);
  const referredEmail = optionalText(row["referredEmail"]);
  const qualifiedAt = optionalInstant(row["qualifiedAt"]);
  const rewardedAt = optionalInstant(row["rewardedAt"]);
  const ledgerTransactionId = optionalText(row["ledgerTransactionId"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    codeId: textOf(row["codeId"]),
    referrerId: textOf(row["referrerId"]),
    status: enumOrThrow(row["status"], REFERRAL_STATUSES, "referral status"),
    createdAt: temporal().Instant.from(textOf(row["createdAt"])),
    ...(referredUserId === undefined ? {} : { referredUserId }),
    ...(referredOrganizationId === undefined ? {} : { referredOrganizationId }),
    ...(referredEmail === undefined ? {} : { referredEmail }),
    ...(reward === undefined ? {} : { reward }),
    ...(qualifiedAt === undefined ? {} : { qualifiedAt }),
    ...(rewardedAt === undefined ? {} : { rewardedAt }),
    ...(ledgerTransactionId === undefined ? {} : { ledgerTransactionId }),
  };
}

const definedOf = (input: object): Record<string, unknown> =>
  Object.fromEntries(
    Object.entries(input).filter(([, value]) => value !== undefined),
  );

/**
 * Referrals: a code per member, attribution when the referred user or
 * organization signs up, and a reward posted once to the ledger when the
 * referral qualifies.
 */
export function createReferrals(options: ReferralsOptions): Referrals {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResultType<string> => requireTenant(options.tenant);

  const referrals = entityList({
    entity: "referral",
    surface: referralListSurface,
    call,
    tenant,
    fn: "list_referrals",
    rowOf: referralOf,
  });

  const codes = entityList({
    entity: "referral_code",
    surface: referralCodeListSurface,
    call,
    tenant,
    fn: "list_referral_codes",
    rowOf: codeOf,
  });

  const client: Referrals = {
    referralPage: referrals.page,
    referralFacets: referrals.facets,
    referralCount: referrals.count,
    codePage: codes.page,
    codeFacets: codes.facets,
    codeCount: codes.count,
    createCode: (input = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "create_referral_code",
          {
            tenant: organizationId,
            ...definedOf({
              referrer_id: input.referrerId,
              code: input.code,
              invitation_id: input.invitationId,
              reward_amount: input.reward?.amount.toString(),
              reward_unit: input.reward?.unit,
              max_uses: input.maxUses,
              expires_at: input.expiresAt?.toString(),
            }),
          },
          (value) => codeOf(value, "create_referral_code"),
        ),
      ),
    attribute: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "attribute_referral",
          {
            tenant: organizationId,
            code: input.code,
            ...definedOf({
              referred_user: input.referredUserId,
              referred_org: input.referredOrganizationId,
              referred_email: input.referredEmail,
            }),
          },
          (value) => referralOf(value, "attribute_referral"),
        ),
      ),
    qualify: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "qualify_referral",
          {
            tenant: organizationId,
            ...definedOf({
              referred_user: input.referredUserId,
              referred_org: input.referredOrganizationId,
              source: input.source,
            }),
          },
          (value) =>
            value === null || value === undefined
              ? undefined
              : referralOf(value, "qualify_referral"),
        ),
      ),
    void: ({ referralId, reason }) =>
      call(
        "void_referral",
        { referral_id: referralId, ...definedOf({ reason }) },
        (value) => referralOf(value, "void_referral"),
      ),
    listCodes: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_referral_codes",
          {
            tenant: organizationId,
            filters: definedOf({
              referrer: list.referrerId,
              limit: list.limit,
            }),
          },
          (value) =>
            recordsOf(value, "list_referral_codes").map((row) =>
              codeOf(row, "list_referral_codes"),
            ),
        ),
      ),
    listReferrals: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_referrals",
          {
            tenant: organizationId,
            filters: definedOf({
              referrer: list.referrerId,
              status: list.status,
              limit: list.limit,
            }),
          },
          (value) =>
            recordsOf(value, "list_referrals").map((row) =>
              referralOf(row, "list_referrals"),
            ),
        ),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "referrals",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
