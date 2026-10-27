import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTenantOptions } from "../../core/block-tenant.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { GuestAction } from "../../core/guest-actions.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { RecordRef } from "../../schema/types.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { GUEST_ACTIONS } from "../../core/guest-actions.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  instantArg,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  stringsOf,
  textOf,
} from "../shared.ts";

export type { GuestAction } from "../../core/guest-actions.ts";

export interface GuestsOptions
  extends BlockTemporalOptions, BlockTenantOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Guests>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

export type GuestStatus = "invited" | "active" | "revoked";

/** Someone outside the organization, invited by email. Never a member. */
export interface Guest {
  readonly id: string;
  readonly organizationId: string;
  readonly email: string;
  readonly name?: string;
  /** Set once the guest accepts. */
  readonly userId?: string;
  /**
   * The party the guest acts for, such as a customer company: they see its
   * invoices and bookings.
   */
  readonly party?: RecordRef;
  readonly status: GuestStatus;
  readonly invitedBy?: string;
  readonly expiresAt?: Temporal.Instant;
  readonly acceptedAt?: Temporal.Instant;
  readonly revokedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** A guest with the one-time token for the invite link. */
export interface GuestInvite extends Guest {
  /**
   * Send it in the invite link; `accept` takes it. Missing when the guest had
   * already accepted, so no new token was issued.
   */
  readonly token?: string;
}

/** One record a guest reaches. */
export interface GuestGrant {
  readonly id: string;
  readonly organizationId: string;
  readonly guestId: string;
  readonly subject: RecordRef;
  /** Always holds `read`. */
  readonly actions: readonly GuestAction[];
  readonly grantedBy?: string;
  readonly expiresAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** A grant on a record, with its guest, for the record's sharing panel. */
export interface RecordGuestGrant extends GuestGrant {
  readonly guest: Guest;
}

/** One organization the caller is a guest of, with their live grants. */
export interface GuestMembership extends Guest {
  readonly grants: readonly GuestGrant[];
}

export interface GuestInviteInput {
  readonly email: string;
  readonly name?: string;
  /** The customer company or person the guest acts for. */
  readonly party?: RecordRef;
  /** When the invite stops working. */
  readonly expiresAt?: Temporal.Instant;
}

export interface GuestGrantInput {
  /** Default `["read"]`; `read` is always added. */
  readonly actions?: readonly GuestAction[];
  readonly expiresAt?: Temporal.Instant;
}

export interface GuestListOptions {
  readonly status?: GuestStatus;
  /** Pages back from a guest's `createdAt`. */
  readonly before?: Temporal.Instant;
  readonly pageSize?: number;
}

export interface Guests {
  /**
   * Invites an email to the block's tenant. Needs `guests.manage`. Inviting the
   * email again issues a new token, or restores a revoked guest.
   */
  invite(input: GuestInviteInput): AsyncResult<GuestInvite>;
  /**
   * The signed-in user accepts an invite. Their confirmed email must match the
   * invite's.
   */
  accept(token: string): AsyncResult<Guest>;
  /** Needs `guests.manage`. Their grants stop counting. */
  revoke(guestId: string): AsyncResult<Guest>;
  /** The tenant's guests, newest first. Needs `guests.read`. */
  list(options?: GuestListOptions): AsyncResult<readonly Guest[]>;
  /**
   * Lets a guest reach one record. Needs `guests.manage`; the record must be in
   * the guest's organization.
   */
  grant(
    guestId: string,
    subject: RecordRef,
    input?: GuestGrantInput,
  ): AsyncResult<GuestGrant>;
  /** `false` when the grant is gone or the caller can't manage it. */
  revokeGrant(grantId: string): AsyncResult<boolean>;
  /** The guests who reach a record. The record decides the tenant. */
  grants(subject: RecordRef): AsyncResult<readonly RecordGuestGrant[]>;
  /** What the caller reaches as a guest, for a portal's home page. */
  mine(): AsyncResult<readonly GuestMembership[]>;
  /** Whether the caller reaches a record as a guest for an action. */
  can(subject: RecordRef, action?: GuestAction): AsyncResult<boolean>;
}

const STATUSES: readonly GuestStatus[] = ["invited", "active", "revoked"];

function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): { readonly [P in K]?: V } {
  // SAFETY: a one-key object literal for the key the caller names.
  return (value === undefined ? {} : { [key]: value }) as {
    readonly [P in K]?: V;
  };
}

function partyOf(row: Record<string, unknown>): RecordRef | undefined {
  const type = optionalText(row["partyType"]);
  const id = optionalText(row["partyId"]);

  return type === undefined || id === undefined ? undefined : { type, id };
}

function guestOf(value: unknown, fn: string): Guest {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    email: textOf(row["email"]),
    status: enumOrThrow(row["status"], STATUSES, "guest status"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("name", optionalText(row["name"])),
    ...optional("userId", optionalText(row["userId"])),
    ...optional("party", partyOf(row)),
    ...optional("invitedBy", optionalText(row["invitedBy"])),
    ...optional("expiresAt", optionalInstant(row["expiresAt"])),
    ...optional("acceptedAt", optionalInstant(row["acceptedAt"])),
    ...optional("revokedAt", optionalInstant(row["revokedAt"])),
  };
}

function grantOf(value: unknown, fn: string): GuestGrant {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    guestId: textOf(row["guestId"]),
    subject: { type: textOf(row["subjectType"]), id: textOf(row["subjectId"]) },
    actions: stringsOf(row["actions"]).map((action) =>
      enumOrThrow(action, GUEST_ACTIONS, "guest action"),
    ),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("grantedBy", optionalText(row["grantedBy"])),
    ...optional("expiresAt", optionalInstant(row["expiresAt"])),
  };
}

/** The `guests` SQL module as typed calls. */
export function createGuests(options: GuestsOptions): Guests {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const client: Guests = {
    invite: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "invite_guest",
          {
            tenant: organizationId,
            email: input.email,
            name: input.name ?? null,
            party_type: input.party?.type ?? null,
            party_id: input.party?.id ?? null,
            expires_at: instantArg(input.expiresAt),
          },
          (value) => {
            const token = optionalText(
              recordOf(value, "invite_guest")["token"],
            );

            return {
              ...guestOf(value, "invite_guest"),
              ...optional("token", token),
            };
          },
        ),
      ),
    accept: (token) =>
      call("accept_guest_invite", { token }, (value) =>
        guestOf(value, "accept_guest_invite"),
      ),
    revoke: (guestId) =>
      call("revoke_guest", { guest_id: guestId }, (value) =>
        guestOf(value, "revoke_guest"),
      ),
    list: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_guests",
          {
            tenant: organizationId,
            status: list.status ?? null,
            before: instantArg(list.before),
            page_size: list.pageSize ?? null,
          },
          (value) =>
            recordsOf(value, "list_guests").map((row) =>
              guestOf(row, "list_guests"),
            ),
        ),
      ),
    grant: (guestId, subject, input = {}) =>
      call(
        "grant_guest_access",
        {
          guest_id: guestId,
          subject_type: subject.type,
          subject_id: subject.id,
          actions: input.actions ?? ["read"],
          expires_at: instantArg(input.expiresAt),
        },
        (value) => grantOf(value, "grant_guest_access"),
      ),
    revokeGrant: (grantId) =>
      call(
        "revoke_guest_access",
        { grant_id: grantId },
        (value) => value === true,
      ),
    grants: (subject) =>
      call(
        "list_guest_grants",
        { subject_type: subject.type, subject_id: subject.id },
        (value) =>
          recordsOf(value, "list_guest_grants").map((row) => ({
            ...grantOf(row, "list_guest_grants"),
            guest: guestOf(row["guest"], "list_guest_grants"),
          })),
      ),
    mine: () =>
      call("my_guest_access", {}, (value) =>
        recordsOf(value, "my_guest_access").map((row) => ({
          ...guestOf(row, "my_guest_access"),
          grants: recordsOf(row["grants"], "my_guest_access").map((grant) =>
            grantOf(grant, "my_guest_access"),
          ),
        })),
      ),
    can: (subject, action = "read") =>
      call(
        "guest_can",
        { subject_type: subject.type, subject_id: subject.id, action },
        (value) => value === true,
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "guests",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
