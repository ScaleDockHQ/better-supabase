import type { ErrorMapper } from "../core/errors.ts";
import type { EventHub } from "../core/events.ts";
import type {
  InvitationEventData,
  KitEventMap,
  KitEventType,
  OrgEventData,
} from "../core/kit-events.ts";
import type { KitTransport } from "../core/kit-transport.ts";
import type { RequestContext } from "../core/plugin.ts";

import { dbError, mapDbError } from "../core/errors.ts";
import { emitKitEvent } from "../core/kit-events.ts";
import { rawError } from "../core/kit-transport.ts";
import { AsyncResult, err, ok, toDbError } from "../core/result.ts";
import { temporal } from "../core/temporal-required.ts";

/**
 * Organization columns by database name: `name`, `slug` and the columns in
 * `kits.organizations.options.attributes`. Other keys are ignored.
 */
export interface OrgAttributes {
  readonly name?: string;
  readonly slug?: string;
  readonly [column: string]: unknown;
}

export interface CreateOrgOptions {
  /** The owner, when the transport runs as the service role. */
  readonly ownerId?: string;
}

export type SlugProblem = "invalid" | "reserved" | "taken";

export interface InviteRequest {
  /** `null` invites to the platform (`kits.access.model: 'catalog'`). */
  readonly organizationId: string | null;
  readonly email: string;
  /** A role name, or a role id or key under the catalog model. */
  readonly role: string;
  /** A Postgres interval such as `'3 days'`. Defaults to `options.validFor`. */
  readonly validFor?: string;
  /** Profile fields to fill in on sign-up. */
  readonly prefill?: Readonly<Record<string, unknown>>;
}

export interface Invitation {
  readonly id: string;
  readonly organizationId: string | null;
  readonly email: string;
  readonly role: string;
  readonly expiresAt: Temporal.Instant;
  readonly invitedBy?: string;
  readonly prefill: Readonly<Record<string, unknown>>;
}

/** What `onInvite` receives: the place to send the email. */
export interface InvitationSent {
  readonly invitation: Invitation;
  /** Put it in the accept link. It is never stored in plain text by default. */
  readonly token: string;
  readonly resent: boolean;
}

export type InvitationStatus =
  | "pending"
  | "accepted"
  | "declined"
  | "revoked"
  | "expired";

export interface InvitationPreview {
  readonly status: InvitationStatus;
  readonly email: string;
  readonly role: string;
  readonly organizationId: string | null;
  readonly expiresAt: Temporal.Instant;
  /** The organization columns in `options.previewColumns`. */
  readonly organization: Readonly<Record<string, unknown>> | null;
  readonly prefill: Readonly<Record<string, unknown>>;
}

export interface SwitchResult {
  readonly organizationId: string;
  /** The active tenant is a claim: refresh the session to get it. */
  readonly refresh: boolean;
}

export interface OrgsOptions {
  /** `sqlTransport(postgres.asUser(claims))` or `rpcTransport(supabase)`. */
  readonly transport: KitTransport;
  /**
   * `kits.<module>.schema`. One schema for both modules, or one per
   * module. Defaults to `better_supabase`.
   */
  readonly schema?:
    | string
    | { readonly organizations?: string; readonly invitations?: string };
  /** `betterSupabase.events`, to emit `org.*` and `invitation.*` kit events. */
  readonly events?: EventHub;
  /** The user acting, for event metadata. */
  readonly actorId?: string;
  readonly context?: RequestContext;
  /**
   * Runs before an invitation is created, after the database checks the
   * caller may invite. Return `false` to refuse (seat limits, plans).
   */
  readonly canInvite?: (request: InviteRequest) => boolean | Promise<boolean>;
  /**
   * Runs after an invitation is created or resent, to send the email. When
   * it throws, the call returns an error and the invitation stays open:
   * call `resendInvitation` to retry.
   */
  readonly onInvite?: (sent: InvitationSent) => void | Promise<void>;
  /** Run before the built-in mapping, as in `betterSupabase.mapError()`. */
  readonly errorMappers?: readonly ErrorMapper[];
}

/**
 * The `organizations` and `invitations` SQL kit modules as typed calls. Each
 * method returns an `AsyncResult`; database errors carry the kit's error
 * code (`ORG_FORBIDDEN`, `INVITATION_INVALID`) as `hint`.
 */
export interface Orgs {
  create(
    attributes: OrgAttributes,
    options?: CreateOrgOptions,
  ): AsyncResult<{ readonly id: string }>;
  update(organizationId: string, attributes: OrgAttributes): AsyncResult<true>;
  /** `false` when it did not exist (or was already soft-deleted). */
  delete(organizationId: string): AsyncResult<boolean>;
  /** Why a slug can't be used, or `undefined` when it can. */
  slugProblem(
    slug: string,
    exceptOrganizationId?: string,
  ): AsyncResult<SlugProblem | undefined>;
  updateMemberRole(
    organizationId: string,
    userId: string,
    role: string,
  ): AsyncResult<true>;
  removeMember(organizationId: string, userId: string): AsyncResult<true>;
  leave(organizationId: string): AsyncResult<true>;
  /** `formerRole` defaults to `options.formerOwnerRole`. */
  transferOwnership(
    organizationId: string,
    newOwnerId: string,
    formerRole?: string,
  ): AsyncResult<true>;
  markUsed(organizationId: string): AsyncResult<boolean>;
  switch(organizationId: string): AsyncResult<SwitchResult>;
  invite(request: InviteRequest): AsyncResult<InvitationSent>;
  resendInvitation(
    invitationId: string,
    validFor?: string,
  ): AsyncResult<InvitationSent>;
  /** `false` when it was not open. */
  revokeInvitation(invitationId: string): AsyncResult<boolean>;
  declineInvitation(token: string): AsyncResult<boolean>;
  /** `undefined` for an unknown token. Callable without a session. */
  previewInvitation(token: string): AsyncResult<InvitationPreview | undefined>;
  /** Returns the organization joined, `null` for a platform invitation. */
  acceptInvitation(
    token: string,
  ): AsyncResult<{ readonly organizationId: string | null }>;
}

const DEFAULT_SCHEMA = "better_supabase";

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const text = (value: unknown): string =>
  typeof value === "string" ? value : String(value);

const optionalText = (value: unknown): string | null =>
  value === null || value === undefined ? null : text(value);

function invitationFrom(row: Record<string, unknown>): Invitation {
  const invitedBy = optionalText(row["invited_by"]);
  return {
    id: text(row["id"]),
    organizationId: optionalText(row["tenant"]),
    email: text(row["email"]),
    role: text(row["role"]),
    expiresAt: temporal().Instant.from(text(row["expires_at"])),
    ...(invitedBy === null ? {} : { invitedBy }),
    prefill: isRecord(row["prefill"]) ? row["prefill"] : {},
  };
}

const STATUSES: ReadonlySet<string> = new Set<InvitationStatus>([
  "pending",
  "accepted",
  "declined",
  "revoked",
  "expired",
]);

function isStatus(value: unknown): value is InvitationStatus {
  return typeof value === "string" && STATUSES.has(value);
}

function previewFrom(row: Record<string, unknown>): InvitationPreview {
  const status = row["status"];
  if (!isStatus(status)) {
    throw new TypeError(`Unknown invitation status ${String(status)}`);
  }
  return {
    status,
    email: text(row["email"]),
    role: text(row["role"]),
    organizationId: optionalText(row["tenant"]),
    expiresAt: temporal().Instant.from(text(row["expires_at"])),
    organization: isRecord(row["organization"]) ? row["organization"] : null,
    prefill: isRecord(row["prefill"]) ? row["prefill"] : {},
  };
}

function recordOf(value: unknown, fn: string): Record<string, unknown> {
  if (!isRecord(value)) {
    throw new TypeError(`${fn} returned ${JSON.stringify(value)}`);
  }
  return value;
}

/** Calls the `organizations` and `invitations` kit functions. */
export function createOrgs(options: OrgsOptions): Orgs {
  const { transport } = options;
  const schemaOf = (module: "organizations" | "invitations"): string =>
    typeof options.schema === "string"
      ? options.schema
      : (options.schema?.[module] ?? DEFAULT_SCHEMA);
  const mappers = options.errorMappers ?? [];

  function run<T>(
    module: "organizations" | "invitations",
    fn: string,
    args: Readonly<Record<string, unknown>>,
    then: (value: unknown) => T | Promise<T>,
  ): AsyncResult<T> {
    return AsyncResult.from(async () => {
      let value: unknown;
      try {
        value = await transport.call(schemaOf(module), fn, args);
      } catch (cause) {
        const raw = rawError(cause);
        return err(raw ? mapDbError(raw, mappers) : toDbError(cause));
      }
      return ok(await then(value));
    });
  }

  function emit<K extends KitEventType>(
    type: K,
    data: KitEventMap[K],
    subject: string,
    tenant?: string | null,
  ): void {
    if (!options.events) return;
    emitKitEvent(options.events, type, data, {
      subject,
      ...(tenant ? { tenant } : {}),
      ...(options.actorId ? { actorId: options.actorId } : {}),
      ...(options.context ? { context: options.context } : {}),
    });
  }

  const orgEvent = (
    type: Extract<KitEventType, `org.${string}`>,
    data: OrgEventData,
  ): void => {
    emit(
      type,
      data,
      `organizations/${data.organizationId}`,
      data.organizationId,
    );
  };

  const invitationEvent = (
    type: Extract<KitEventType, `invitation.${string}`>,
    data: InvitationEventData,
  ): void => {
    emit(
      type,
      data,
      `invitations/${data.invitationId}`,
      data.organizationId ?? null,
    );
  };

  const sent = async (
    value: unknown,
    fn: string,
    resent: boolean,
  ): Promise<InvitationSent> => {
    const row = recordOf(value, fn);
    const invitation = invitationFrom(row);
    const result: InvitationSent = {
      invitation,
      token: text(row["token"]),
      resent,
    };
    invitationEvent(resent ? "invitation.resent" : "invitation.created", {
      invitationId: invitation.id,
      ...(invitation.organizationId === null
        ? {}
        : { organizationId: invitation.organizationId }),
      email: invitation.email,
      role: invitation.role,
    });
    await options.onInvite?.(result);
    return result;
  };

  return {
    create(attributes, createOptions) {
      const attrs = {
        ...attributes,
        ...(createOptions?.ownerId ? { owner_id: createOptions.ownerId } : {}),
      };
      return run("organizations", "create_organization", { attrs }, (value) => {
        const id = text(value);
        orgEvent("org.created", {
          organizationId: id,
          ...((createOptions?.ownerId ?? options.actorId)
            ? { userId: createOptions?.ownerId ?? options.actorId }
            : {}),
        });
        return { id };
      });
    },
    update(organizationId, attributes) {
      return run(
        "organizations",
        "update_organization",
        { org: organizationId, attrs: attributes },
        () => {
          orgEvent("org.updated", { organizationId });
          return true as const;
        },
      );
    },
    delete(organizationId) {
      return run(
        "organizations",
        "delete_organization",
        { org: organizationId },
        (value) => {
          if (value === true) orgEvent("org.deleted", { organizationId });
          return value === true;
        },
      );
    },
    slugProblem(slug, exceptOrganizationId) {
      return run(
        "organizations",
        "organization_slug_problem",
        { value: slug, except_org: exceptOrganizationId },
        (value) => {
          if (value === null) return;
          if (value === "invalid" || value === "reserved" || value === "taken")
            return value;
          throw new TypeError(`Unknown slug problem ${String(value)}`);
        },
      );
    },
    updateMemberRole(organizationId, userId, role) {
      return run(
        "organizations",
        "update_member_role",
        { org: organizationId, member: userId, role },
        () => {
          orgEvent("org.role_changed", { organizationId, userId, role });
          return true as const;
        },
      );
    },
    removeMember(organizationId, userId) {
      return run(
        "organizations",
        "remove_member",
        { org: organizationId, member: userId },
        () => {
          orgEvent("org.member_removed", { organizationId, userId });
          return true as const;
        },
      );
    },
    leave(organizationId) {
      return run(
        "organizations",
        "leave_organization",
        { org: organizationId },
        () => {
          orgEvent("org.member_left", {
            organizationId,
            ...(options.actorId ? { userId: options.actorId } : {}),
          });
          return true as const;
        },
      );
    },
    transferOwnership(organizationId, newOwnerId, formerRole) {
      return run(
        "organizations",
        "transfer_ownership",
        { org: organizationId, new_owner: newOwnerId, former_role: formerRole },
        () => {
          orgEvent("org.ownership_transferred", {
            organizationId,
            userId: newOwnerId,
          });
          return true as const;
        },
      );
    },
    markUsed(organizationId) {
      return run(
        "organizations",
        "mark_used",
        { org: organizationId },
        (value) => value === true,
      );
    },
    switch(organizationId) {
      return run(
        "organizations",
        "switch_organization",
        { org: organizationId },
        (value) => {
          const row = recordOf(value, "switch_organization");
          orgEvent("org.switched", {
            organizationId,
            ...(options.actorId ? { userId: options.actorId } : {}),
          });
          return {
            organizationId: text(row["organization_id"]),
            refresh: row["refresh"] === true,
          };
        },
      );
    },
    invite(request) {
      return AsyncResult.from(async () => {
        if (options.canInvite && !(await options.canInvite(request))) {
          return err(
            dbError("forbidden", "The invitation was refused", {
              hint: "INVITATION_FORBIDDEN",
            }),
          );
        }
        return run(
          "invitations",
          "invite_member",
          {
            tenant: request.organizationId,
            invitee_email: request.email,
            invitee_role: request.role,
            valid_for: request.validFor,
            prefill: request.prefill,
          },
          (value) => sent(value, "invite_member", false),
        );
      });
    },
    resendInvitation(invitationId, validFor) {
      return run(
        "invitations",
        "resend_invitation",
        { invitation_id: invitationId, valid_for: validFor },
        (value) => sent(value, "resend_invitation", true),
      );
    },
    revokeInvitation(invitationId) {
      return run(
        "invitations",
        "revoke_invitation",
        { invitation_id: invitationId },
        (value) => {
          if (value === true) {
            invitationEvent("invitation.revoked", { invitationId });
          }
          return value === true;
        },
      );
    },
    declineInvitation(token) {
      return run(
        "invitations",
        "decline_invitation",
        { token },
        (value) => value === true,
      );
    },
    previewInvitation(token) {
      return run("invitations", "invitation_preview", { token }, (value) =>
        value === null
          ? undefined
          : previewFrom(recordOf(value, "invitation_preview")),
      );
    },
    acceptInvitation(token) {
      return run("invitations", "accept_invitation", { token }, (value) => {
        const organizationId = optionalText(value);
        if (organizationId !== null) {
          orgEvent("org.member_added", {
            organizationId,
            ...(options.actorId ? { userId: options.actorId } : {}),
          });
        }
        return { organizationId };
      });
    },
  };
}
