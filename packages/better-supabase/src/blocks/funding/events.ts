import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** The record an award is for, its funder, product and state. */
interface FundingAwardEventBase {
  readonly organizationId: string;
  readonly fundingAwardId: string;
  readonly fundingProductId: string;
  readonly funderId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  /** `requested`, `active`, `ended` or `canceled`. */
  readonly status: string;
}

/** `funding_award.created`: a funder awarded units of a product to a record. */
export type FundingAwardCreatedEventData = FundingAwardEventBase;

/** `funding_award.updated`: the units, period, dates or reference changed. */
export type FundingAwardUpdatedEventData = FundingAwardEventBase;

/** `funding_award.ended`: the award ended or was canceled. */
export interface FundingAwardEndedEventData extends FundingAwardEventBase {
  /** ISO date; null for a canceled award that never started. */
  readonly endsOn: string | null;
}

/** `funding_award.exceeded`: a period used more units than the award allows. */
export interface FundingAwardExceededEventData extends FundingAwardEventBase {
  /** ISO date the period starts on. */
  readonly periodStart: string;
  readonly awarded: number;
  readonly used: number;
}

/** `funding_delivery.registered`: care or service was registered on an award. */
export interface FundingDeliveryRegisteredEventData {
  readonly organizationId: string;
  readonly fundingAwardId: string;
  readonly fundingDeliveryId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  /** `time_entry`, `booking` or `manual`. */
  readonly sourceType: string;
  readonly sourceId: string | null;
  /** ISO date. */
  readonly deliveredOn: string;
  readonly units: number;
}

/** A claim to one funder for one period. */
interface FundingClaimEventBase {
  readonly organizationId: string;
  readonly fundingClaimId: string;
  readonly funderId: string;
  readonly number: string;
  /** `draft`, `sent`, `accepted`, `partially_accepted` or `rejected`. */
  readonly status: string;
  readonly periodStart: string;
  readonly periodEnd: string;
  /** Minor units, as text. */
  readonly total: string;
  readonly currency: string;
}

/** `funding_claim.created`: approved deliveries were gathered into a claim. */
export type FundingClaimCreatedEventData = FundingClaimEventBase;

/** `funding_claim.sent`: the claim went to the funder. */
export interface FundingClaimSentEventData extends FundingClaimEventBase {
  readonly externalRef: string | null;
}

/** `funding_claim.responded`: the funder accepted or rejected its lines. */
export type FundingClaimRespondedEventData = FundingClaimEventBase;

/** `funding_claim.deleted`: a draft claim was deleted; its deliveries are free. */
export type FundingClaimDeletedEventData = FundingClaimEventBase;

/** The events of the `funding` block: type to data. */
export type FundingEvents = {
  readonly "funding_award.created": FundingAwardCreatedEventData;
  readonly "funding_award.updated": FundingAwardUpdatedEventData;
  readonly "funding_award.ended": FundingAwardEndedEventData;
  readonly "funding_award.exceeded": FundingAwardExceededEventData;
  readonly "funding_delivery.registered": FundingDeliveryRegisteredEventData;
  readonly "funding_claim.created": FundingClaimCreatedEventData;
  readonly "funding_claim.sent": FundingClaimSentEventData;
  readonly "funding_claim.responded": FundingClaimRespondedEventData;
  readonly "funding_claim.deleted": FundingClaimDeletedEventData;
};

/** The `funding` block's event types, for its manifest and `onBlockEvent`. */
export const fundingEvents: Events<FundingEvents> = defineEvents({
  "funding_award.created": event<FundingAwardCreatedEventData>(),
  "funding_award.updated": event<FundingAwardUpdatedEventData>(),
  "funding_award.ended": event<FundingAwardEndedEventData>(),
  "funding_award.exceeded": event<FundingAwardExceededEventData>(),
  "funding_delivery.registered": event<FundingDeliveryRegisteredEventData>(),
  "funding_claim.created": event<FundingClaimCreatedEventData>(),
  "funding_claim.sent": event<FundingClaimSentEventData>(),
  "funding_claim.responded": event<FundingClaimRespondedEventData>(),
  "funding_claim.deleted": event<FundingClaimDeletedEventData>(),
});
