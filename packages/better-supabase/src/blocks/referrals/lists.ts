import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `referralPage`, `referralFacets` and `referralCount` accept for a
 * referral (ADR 0749). The manifest declares the same names, and the SQL list
 * function `list_referrals` implements them.
 */
export const referralListSurface: EntityListSurface = {
  sorts: ["createdAt"],
  facets: ["status", "referrer"],
  filters: ["status", "referrer"],
};

/**
 * What `codePage`, `codeFacets` and `codeCount` accept for a referral code. The
 * SQL list function is `list_referral_codes`.
 */
export const referralCodeListSurface: EntityListSurface = {
  sorts: ["createdAt"],
  facets: ["referrer"],
  filters: ["referrer"],
};
