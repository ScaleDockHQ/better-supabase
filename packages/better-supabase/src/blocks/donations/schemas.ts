import type { EntitySchema } from "../entity-schema.ts";
import type { DonationFundInput, GiftInput, PledgeInput } from "./donations.ts";

import { entitySchema, moneyField } from "../entity-schema.ts";

const FREQUENCIES = ["weekly", "monthly", "quarterly", "yearly"] as const;

/** What `recordGift` takes, with the bounds the SQL checks. */
export const giftInputSchema: EntitySchema<GiftInput> = entitySchema<GiftInput>(
  {
    title: "GiftInput",
    fields: {
      donor: {
        kind: "json",
        description: "The donor, a registered subject: `{ type, id }`.",
      },
      amount: moneyField,
      fundId: { kind: "uuid", optional: true },
      receivedOn: { kind: "plainDate", optional: true },
      method: { kind: "string", optional: true, maxLength: 40 },
      note: { kind: "string", optional: true, maxLength: 2000 },
      pledgeId: { kind: "uuid", optional: true },
      periodStart: { kind: "plainDate", optional: true },
      fields: {
        kind: "json",
        optional: true,
        description: "The extra columns to set.",
      },
    },
  },
);

/** What `createPledge` takes. */
export const pledgeInputSchema: EntitySchema<PledgeInput> =
  entitySchema<PledgeInput>({
    title: "PledgeInput",
    fields: {
      donor: {
        kind: "json",
        description: "The donor, a registered subject: `{ type, id }`.",
      },
      amount: moneyField,
      frequency: { kind: "enum", values: FREQUENCIES, optional: true },
      fundId: { kind: "uuid", optional: true },
      startsOn: { kind: "plainDate", optional: true },
      endsOn: { kind: "plainDate", optional: true },
      provider: { kind: "string", optional: true, maxLength: 100 },
      providerCustomer: { kind: "string", optional: true, maxLength: 200 },
      note: { kind: "string", optional: true, maxLength: 2000 },
    },
  });

/** What `saveFund` takes. */
export const donationFundInputSchema: EntitySchema<DonationFundInput> =
  entitySchema<DonationFundInput>({
    title: "DonationFundInput",
    fields: {
      key: {
        kind: "string",
        minLength: 1,
        maxLength: 63,
        description: "Lowercase letters, digits and underscores.",
      },
      name: { kind: "string", minLength: 1, maxLength: 200 },
      kind: { kind: "enum", values: ["fund", "campaign"], optional: true },
      goal: { ...moneyField, optional: true },
      startsOn: { kind: "plainDate", optional: true },
      endsOn: { kind: "plainDate", optional: true },
    },
  });
