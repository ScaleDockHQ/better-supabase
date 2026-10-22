import type { EntitySchema } from "../entity-schema.ts";
import type { GuestGrantInput, GuestInviteInput } from "./guests.ts";

import { GUEST_ACTIONS } from "../../core/guest-actions.ts";
import { entitySchema } from "../entity-schema.ts";

/** What `invite` takes, with the bounds the SQL checks. */
export const guestInviteSchema: EntitySchema<GuestInviteInput> =
  entitySchema<GuestInviteInput>({
    title: "GuestInviteInput",
    fields: {
      email: { kind: "string", minLength: 3, maxLength: 320 },
      name: { kind: "string", optional: true, minLength: 1, maxLength: 200 },
      party: {
        kind: "json",
        optional: true,
        description: "The record the guest acts for: `{ type, id }`.",
      },
      expiresAt: { kind: "instant", optional: true },
    },
  });

const ACTIONS = {
  kind: "enum",
  values: GUEST_ACTIONS,
  optional: true,
  array: true,
  description: "`read` is always added.",
} as const;

/** What `grant` takes after the guest and the record. */
export const guestGrantSchema: EntitySchema<GuestGrantInput> =
  entitySchema<GuestGrantInput>({
    title: "GuestGrantInput",
    fields: {
      actions: ACTIONS,
      expiresAt: { kind: "instant", optional: true },
    },
  });

/** What the section's `grant` write takes. */
export interface GuestSectionGrantInput extends GuestGrantInput {
  readonly guestId: string;
}

export const guestSectionGrantSchema: EntitySchema<GuestSectionGrantInput> =
  entitySchema<GuestSectionGrantInput>({
    title: "GuestSectionGrantInput",
    fields: {
      guestId: { kind: "uuid" },
      actions: ACTIONS,
      expiresAt: { kind: "instant", optional: true },
    },
  });
