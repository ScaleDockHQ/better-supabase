import type {
  BlockEventType,
  InvitationEventData,
  OrganizationEventData,
} from "../../core/block-events.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { EventHub } from "../../core/events.ts";
import type { RequestContext } from "../../core/plugin.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { InvitationError } from "../../sql/modules/invitations-tables.ts";
import type { OrganizationsEvents } from "./events.ts";

import { blockEmitter } from "../../core/block-events.ts";
import {
  type BlockFields,
  blockFields,
  type FieldsOf,
  readAllFields,
  readFields,
  type RowFields,
  rowFields,
} from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  applyTemporal,
  blockCall,
  type BlockTemporalOptions,
  DEFAULT_BLOCK_SCHEMA,
  isRecord,
  recordsOf,
} from "../shared.ts";

/**
 * Organization columns by database name: `name`, `slug`, the columns in
 * `blocks.organizations.options.attributes` and the ones
 * `options.extraColumns` adds. Other keys are ignored.
 */
export interface OrganizationAttributes {
  readonly name?: string;
  readonly slug?: string;
  readonly [column: string]: unknown;
}

export interface CreateOrganizationOptions {
  /** The owner, when the transport runs as the service role. */
  readonly ownerId?: string;
}

export type SlugProblem = "invalid" | "reserved" | "taken";

export interface InviteRequest<I extends object = Record<never, never>> {
  /** `null` invites to the platform (`blocks.access.model: 'catalog'`). */
  readonly organizationId: string | null;
  readonly email: string;
  /** A role name, or a role id or key under the catalog model. */
  readonly role: string;
  /** A Postgres interval such as `'3 days'`. Defaults to `options.validFor`. */
  readonly validFor?: string;
  /** Profile fields to fill in on sign-up. */
  readonly prefill?: Readonly<Record<string, unknown>>;
  /**
   * Values for the invitations table's extra columns
   * (`blocks.invitations.options.extraColumns`), checked by
   * `options.invitationFields`.
   */
  readonly fields?: Partial<I> & Readonly<Record<string, unknown>>;
}

/** An invitation. `I` types the extra columns `options.invitationFields` describes. */
export interface Invitation<I extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string | null;
  readonly email: string;
  readonly role: string;
  readonly expiresAt: Temporal.Instant;
  /** Absent when the invitations table has no `createdAt` column. */
  readonly createdAt?: Temporal.Instant;
  readonly invitedBy?: string;
  /** The organization's id and `options.previewColumns`; `null` for a platform invitation. */
  readonly organization: Readonly<Record<string, unknown>> | null;
  readonly prefill: Readonly<Record<string, unknown>>;
  /**
   * The inviter's `id` and public profile fields (`username`, `fullName`,
   * `firstName`, `lastName`, `avatar`, as the profiles module maps them).
   * `null` without the profiles module, an `invitedBy` column or the
   * inviter's profile.
   */
  readonly inviter: Readonly<Record<string, unknown>> | null;
  /** The keys an `invitation_preview_extra` hook added, such as a role label. */
  readonly extra: Readonly<Record<string, unknown>>;
  /** The extra columns of an organization invitation, by column name. */
  readonly fields: RowFields<I>;
}

/** What `updateInvitation` changes; a missing key keeps the current value. */
export interface InvitationChanges {
  readonly email?: string;
  /** A role name, or a role id or key under the catalog model. */
  readonly role?: string;
  /** Replaces the profile fields to fill in on sign-up. */
  readonly prefill?: Readonly<Record<string, unknown>>;
}

/** What `onInvite` receives: the place to send the email. */
export interface InvitationSent<I extends object = Record<never, never>> {
  readonly invitation: Invitation<I>;
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
  /**
   * The keys an `invitation_preview_extra` hook added, such as a role's
   * display name or branding. Empty without the hook.
   */
  readonly extra: Readonly<Record<string, unknown>>;
}

export interface SwitchResult {
  readonly organizationId: string;
  /** The active tenant is a claim: refresh the session to get it. */
  readonly refresh: boolean;
}

/**
 * A membership `list_my_organizations` returns. The attribute and extra
 * columns follow under their database names, parsed by `options.fields`
 * when it is set.
 */
export interface OrganizationMembership {
  readonly id: string;
  readonly name: string;
  readonly slug?: string;
  readonly role: string;
  readonly disabledAt?: Temporal.Instant;
  readonly [column: string]: unknown;
}

/** A row `list_members` returns. */
export interface OrganizationMember {
  readonly userId: string;
  readonly role: string;
  readonly disabledAt?: Temporal.Instant;
}

/** An open invitation `list_organization_invitations` returns. */
export interface OrganizationInvitationRow {
  readonly id: string;
  readonly email: string;
  readonly role: string;
  readonly expiresAt?: Temporal.Instant;
}

export interface OrganizationsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
  SI extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  /**
   * A Standard Schema for the organization's extra columns
   * (`options.attributes` and `options.extraColumns`), keyed by database
   * name. It types and parses them on `mine()`, and validates them on
   * `create` and `update`, which return a `validation` error for a bad value.
   */
  readonly fields?: S;
  /**
   * A Standard Schema for the invitations table's extra columns
   * (`blocks.invitations.options.extraColumns`). It validates them on
   * `invite` and parses them on every invitation read.
   */
  readonly invitationFields?: SI;
  /** `withBlockHooks` hooks around the methods, such as a seat limit on `invite`. */
  readonly hooks?: NoInfer<
    BlockHooks<Organizations<FieldsOf<S>, FieldsOf<SI>>>
  >;
  /** `sqlTransport(postgres.asUser(claims))` or `rpcTransport(supabase)`. */
  readonly transport: BlockTransport;
  /**
   * The schema holding the functions: `blocks.<module>.schema` with
   * `sqlTransport`, the exposed API schema of wrappers with `rpcTransport`.
   * One schema for both modules, or one per module. Defaults to
   * `better_supabase`.
   */
  readonly schema?:
    | string
    | { readonly organizations?: string; readonly invitations?: string };
  /** `betterSupabase.events`, to emit `organization.*` and `invitation.*` block events. */
  readonly events?: EventHub;
  /** The user acting, for event metadata. */
  readonly actorId?: string;
  readonly context?: RequestContext;
  /**
   * Runs before an invitation is created, after the database checks the
   * caller may invite. Return `false` to refuse (seat limits, plans).
   */
  readonly canInvite?: (
    request: InviteRequest<FieldsOf<SI>>,
  ) => boolean | Promise<boolean>;
  /**
   * Runs after an invitation is created or resent, to send the email. When
   * it throws, the call returns an error and the invitation stays open:
   * call `resendInvitation` to retry.
   */
  readonly onInvite?: (
    sent: InvitationSent<FieldsOf<SI>>,
  ) => void | Promise<void>;
  /** Error mappers that run before the built-in ones, as in `betterSupabase.mapError()`. */
  readonly mappers?: readonly ErrorMapper[];
}

/**
 * The `hint` of an invitation error: `INVITATION_EXPIRED` for an open
 * invitation past its expiry, `INVITATION_INVALID` for one that is unknown,
 * accepted, declined or revoked, and the other `INVITATION_*` codes.
 */
export type InvitationErrorHint = InvitationError;

/**
 * The `organizations` and `invitations` SQL modules as typed calls. Each
 * method returns an `AsyncResult`; database errors carry the module's error
 * code (`ORGANIZATION_FORBIDDEN`, `INVITATION_EXPIRED`) as `hint`. `F` is
 * the extra fields `options.fields` describes.
 */
export interface Organizations<
  F extends object = Record<never, never>,
  I extends object = Record<never, never>,
> {
  create(
    attributes: OrganizationAttributes & Partial<F>,
    options?: CreateOrganizationOptions,
  ): AsyncResult<{ readonly id: string }>;
  update(
    organizationId: string,
    attributes: OrganizationAttributes & Partial<F>,
  ): AsyncResult<true>;
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
  suspendMember(organizationId: string, userId: string): AsyncResult<boolean>;
  resumeMember(organizationId: string, userId: string): AsyncResult<boolean>;
  leave(organizationId: string): AsyncResult<true>;
  /** `formerRole` defaults to `options.formerOwnerRole`. */
  transferOwnership(
    organizationId: string,
    newOwnerId: string,
    formerRole?: string,
  ): AsyncResult<true>;
  markUsed(organizationId: string): AsyncResult<boolean>;
  switch(organizationId: string): AsyncResult<SwitchResult>;
  /** Organizations the caller belongs to. */
  mine(): AsyncResult<readonly (OrganizationMembership & F)[]>;
  members(organizationId: string): AsyncResult<readonly OrganizationMember[]>;
  invitations(
    organizationId: string,
  ): AsyncResult<readonly OrganizationInvitationRow[]>;
  invite(request: InviteRequest<I>): AsyncResult<InvitationSent<I>>;
  resendInvitation(
    invitationId: string,
    validFor?: string,
  ): AsyncResult<InvitationSent<I>>;
  /**
   * A new email, role or prefill for an open invitation, with the checks
   * `invite` makes. The token and expiry stay, so the link already sent
   * keeps working; call `resendInvitation` to mail the new address. An
   * expired invitation fails with `INVITATION_EXPIRED`; resend it first.
   */
  updateInvitation(
    invitationId: string,
    changes: InvitationChanges,
  ): AsyncResult<Invitation<I>>;
  /** `false` when it was not open. */
  revokeInvitation(invitationId: string): AsyncResult<boolean>;
  declineInvitation(token: string): AsyncResult<boolean>;
  /** `undefined` for an unknown token. Callable without a session. */
  previewInvitation(token: string): AsyncResult<InvitationPreview | undefined>;
  /** Returns the organization joined, `null` for a platform invitation. */
  acceptInvitation(
    token: string,
  ): AsyncResult<{ readonly organizationId: string | null }>;
  acceptInvitationById(
    invitationId: string,
  ): AsyncResult<{ readonly organizationId: string | null }>;
  declineInvitationById(invitationId: string): AsyncResult<boolean>;
  myInvitations(): AsyncResult<readonly Invitation<I>[]>;
}

const text = (value: unknown): string =>
  typeof value === "string" ? value : String(value);

const optionalText = (value: unknown): string | null =>
  value === null || value === undefined ? null : text(value);

const extraOf = (
  row: Record<string, unknown>,
  known: ReadonlySet<string>,
): Record<string, unknown> =>
  Object.fromEntries(Object.entries(row).filter(([key]) => !known.has(key)));

const INVITATION_KEYS: ReadonlySet<string> = new Set([
  "id",
  "tenant",
  "email",
  "role",
  "expires_at",
  "created_at",
  "invited_by",
  "organization",
  "prefill",
  "inviter",
  "token",
  "fields",
]);

function invitationFrom(row: Record<string, unknown>): Invitation {
  const invitedBy = optionalText(row["invited_by"]);
  const createdAt = optionalText(row["created_at"]);
  return {
    id: text(row["id"]),
    organizationId: optionalText(row["tenant"]),
    email: text(row["email"]),
    role: text(row["role"]),
    expiresAt: temporal().Instant.from(text(row["expires_at"])),
    ...(createdAt === null
      ? {}
      : { createdAt: temporal().Instant.from(createdAt) }),
    ...(invitedBy === null ? {} : { invitedBy }),
    organization: isRecord(row["organization"]) ? row["organization"] : null,
    prefill: isRecord(row["prefill"]) ? row["prefill"] : {},
    inviter: isRecord(row["inviter"]) ? row["inviter"] : null,
    extra: extraOf(row, INVITATION_KEYS),
    fields: rowFields(row["fields"]),
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

const PREVIEW_KEYS: ReadonlySet<string> = new Set([
  "status",
  "email",
  "role",
  "tenant",
  "expires_at",
  "organization",
  "prefill",
]);

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
    extra: extraOf(row, PREVIEW_KEYS),
  };
}

const disabledAtOf = (
  row: Record<string, unknown>,
): { readonly disabledAt?: Temporal.Instant } => {
  const disabledAt = optionalText(row["disabled_at"]);
  return disabledAt === null
    ? {}
    : { disabledAt: temporal().Instant.from(disabledAt) };
};

function recordOf(value: unknown, fn: string): Record<string, unknown> {
  if (!isRecord(value)) {
    throw new TypeError(`${fn} returned ${JSON.stringify(value)}`);
  }
  return value;
}

const MEMBERSHIP_KEYS: ReadonlySet<string> = new Set([
  "id",
  "name",
  "slug",
  "role",
  "disabledAt",
]);

/** Splits `name` and `slug`, which the block types, from the extra columns `fields` checks. */
const splitAttributes = (
  attributes: OrganizationAttributes,
): {
  readonly base: OrganizationAttributes;
  readonly extra: Record<string, unknown>;
} => {
  const { name, slug, ...extra } = attributes;
  return {
    base: {
      ...(name === undefined ? {} : { name }),
      ...(slug === undefined ? {} : { slug }),
    },
    extra,
  };
};

/** Calls the `organizations` and `invitations` block functions. */
export function createOrganizations<
  S extends StandardSchemaV1 | undefined = undefined,
  SI extends StandardSchemaV1 | undefined = undefined,
>(
  options: OrganizationsOptions<S, SI>,
): Organizations<FieldsOf<S>, FieldsOf<SI>> {
  const client = organizationsClient<FieldsOf<S>, FieldsOf<SI>>(options);
  return withBlockHooks(client, options.hooks, {
    block: "organizations",
    ...(options.events ? { logger: options.events.logger } : {}),
  });
}

function organizationsClient<F extends object, I extends object>(
  options: OrganizationsOptions<
    StandardSchemaV1 | undefined,
    StandardSchemaV1 | undefined
  >,
): Organizations<F, I> {
  applyTemporal(options);
  const fields: BlockFields<F> = blockFields(
    options.fields,
    "organization fields",
  );
  const invitationFields: BlockFields<I> = blockFields(
    options.invitationFields,
    "invitation fields",
  );
  const checked = (
    attributes: OrganizationAttributes,
  ): AsyncResult<OrganizationAttributes> =>
    AsyncResult.from(async () => {
      const { base, extra } = splitAttributes(attributes);
      const result = await fields.write(extra);
      return result.ok ? ok({ ...result.data, ...base }) : result;
    });
  const { transport } = options;
  const schemaOf = (module: "organizations" | "invitations"): string =>
    typeof options.schema === "string"
      ? options.schema
      : (options.schema?.[module] ?? DEFAULT_BLOCK_SCHEMA);
  const mappers = options.mappers ?? [];
  const calls = {
    organizations: blockCall(transport, schemaOf("organizations"), mappers),
    invitations: blockCall(transport, schemaOf("invitations"), mappers),
  };

  function run<T>(
    module: "organizations" | "invitations",
    fn: string,
    args: Readonly<Record<string, unknown>>,
    then: (value: unknown) => T | Promise<T>,
  ): AsyncResult<T> {
    return calls[module](fn, args, then);
  }

  const emit = blockEmitter<OrganizationsEvents>(options);

  const organizationEvent = (
    type: Extract<
      BlockEventType<OrganizationsEvents>,
      `organization.${string}`
    >,
    data: OrganizationEventData,
  ): void => {
    emit(
      type,
      data,
      `organizations/${data.organizationId}`,
      data.organizationId,
    );
  };

  const invitationEvent = (
    type: Extract<BlockEventType<OrganizationsEvents>, `invitation.${string}`>,
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
  ): Promise<InvitationSent<I>> => {
    const row = recordOf(value, fn);
    const invitation = await readFields(
      invitationFields,
      invitationFrom(row),
    ).orThrow();
    const result: InvitationSent<I> = {
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

  const accepted = (
    value: unknown,
  ): { readonly organizationId: string | null } => {
    const organizationId = optionalText(value);
    if (organizationId !== null) {
      organizationEvent("organization.member_added", {
        organizationId,
        ...(options.actorId ? { userId: options.actorId } : {}),
      });
    }
    return { organizationId };
  };

  return {
    create(attributes, createOptions) {
      return checked(attributes).andThen((valid) => {
        const attrs = {
          ...valid,
          ...(createOptions?.ownerId
            ? { owner_id: createOptions.ownerId }
            : {}),
        };
        return run(
          "organizations",
          "create_organization",
          { attrs },
          (value) => {
            const id = text(value);
            organizationEvent("organization.created", {
              organizationId: id,
              ...((createOptions?.ownerId ?? options.actorId)
                ? { userId: createOptions?.ownerId ?? options.actorId }
                : {}),
            });
            return { id };
          },
        );
      });
    },
    update(organizationId, attributes) {
      return checked(attributes).andThen((valid) =>
        run(
          "organizations",
          "update_organization",
          { organization: organizationId, attrs: valid },
          () => {
            organizationEvent("organization.updated", { organizationId });
            return true as const;
          },
        ),
      );
    },
    delete(organizationId) {
      return run(
        "organizations",
        "delete_organization",
        { organization: organizationId },
        (value) => {
          if (value === true) {
            organizationEvent("organization.deleted", { organizationId });
          }
          return value === true;
        },
      );
    },
    slugProblem(slug, exceptOrganizationId) {
      return run(
        "organizations",
        "organization_slug_problem",
        { value: slug, except_organization: exceptOrganizationId },
        (value) => {
          if (value === null) {
            return;
          }
          if (
            value === "invalid" ||
            value === "reserved" ||
            value === "taken"
          ) {
            return value;
          }
          throw new TypeError(`Unknown slug problem ${String(value)}`);
        },
      );
    },
    updateMemberRole(organizationId, userId, role) {
      return run(
        "organizations",
        "update_member_role",
        { organization: organizationId, member: userId, role },
        () => {
          organizationEvent("organization.role_changed", {
            organizationId,
            userId,
            role,
          });
          return true as const;
        },
      );
    },
    removeMember(organizationId, userId) {
      return run(
        "organizations",
        "remove_member",
        { organization: organizationId, member: userId },
        () => {
          organizationEvent("organization.member_removed", {
            organizationId,
            userId,
          });
          return true as const;
        },
      );
    },
    suspendMember(organizationId, userId) {
      return run(
        "organizations",
        "suspend_member",
        { organization: organizationId, member: userId },
        (value) => {
          if (value === true) {
            organizationEvent("organization.member_suspended", {
              organizationId,
              userId,
            });
          }
          return value === true;
        },
      );
    },
    resumeMember(organizationId, userId) {
      return run(
        "organizations",
        "resume_member",
        { organization: organizationId, member: userId },
        (value) => {
          if (value === true) {
            organizationEvent("organization.member_resumed", {
              organizationId,
              userId,
            });
          }
          return value === true;
        },
      );
    },
    leave(organizationId) {
      return run(
        "organizations",
        "leave_organization",
        { organization: organizationId },
        () => {
          organizationEvent("organization.member_left", {
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
        {
          organization: organizationId,
          new_owner: newOwnerId,
          former_role: formerRole,
        },
        () => {
          organizationEvent("organization.ownership_transferred", {
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
        { organization: organizationId },
        (value) => value === true,
      );
    },
    switch(organizationId) {
      return run(
        "organizations",
        "switch_organization",
        { organization: organizationId },
        (value) => {
          const row = recordOf(value, "switch_organization");
          organizationEvent("organization.switched", {
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
    mine() {
      return run("organizations", "list_my_organizations", {}, (value) =>
        recordsOf(value, "list_my_organizations"),
      ).andThen(async (rows) => {
        const memberships: (OrganizationMembership & F)[] = [];
        for (const row of rows) {
          const attributes = isRecord(row["attributes"])
            ? Object.fromEntries(
                Object.entries(row["attributes"]).filter(
                  ([key]) => !MEMBERSHIP_KEYS.has(key),
                ),
              )
            : {};
          const parsed = await fields.read(attributes);
          if (!parsed.ok) {
            return parsed;
          }
          const slug = optionalText(row["slug"]);
          memberships.push({
            ...parsed.data,
            id: text(row["id"]),
            name: text(row["name"]),
            ...(slug === null ? {} : { slug }),
            role: text(row["role"]),
            ...disabledAtOf(row),
          });
        }
        return ok(memberships);
      });
    },
    members(organizationId) {
      return run(
        "organizations",
        "list_members",
        { organization: organizationId },
        (value) =>
          recordsOf(value, "list_members").map((row) => ({
            userId: text(row["user_id"]),
            role: text(row["role"]),
            ...disabledAtOf(row),
          })),
      );
    },
    invitations(organizationId) {
      return run(
        "organizations",
        "list_organization_invitations",
        { organization: organizationId },
        (value) =>
          recordsOf(value, "list_organization_invitations").map((row) => {
            const expiresAt = optionalText(row["expires_at"]);
            return {
              id: text(row["id"]),
              email: text(row["email"]),
              role: text(row["role"]),
              ...(expiresAt === null
                ? {}
                : { expiresAt: temporal().Instant.from(expiresAt) }),
            };
          }),
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
        const checked =
          request.fields === undefined
            ? ok(undefined)
            : await invitationFields.write({ ...request.fields });
        if (!checked.ok) {
          return checked;
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
            fields: checked.data,
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
    updateInvitation(invitationId, changes) {
      return run(
        "invitations",
        "update_invitation",
        {
          invitation_id: invitationId,
          invitee_email: changes.email,
          invitee_role: changes.role,
          prefill: changes.prefill,
        },
        (value) => {
          const invitation = invitationFrom(
            recordOf(value, "update_invitation"),
          );
          invitationEvent("invitation.updated", {
            invitationId: invitation.id,
            ...(invitation.organizationId === null
              ? {}
              : { organizationId: invitation.organizationId }),
            email: invitation.email,
            role: invitation.role,
          });
          return invitation;
        },
      ).andThen((invitation) => readFields(invitationFields, invitation));
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
      return run("invitations", "accept_invitation", { token }, accepted);
    },
    acceptInvitationById(invitationId) {
      return run(
        "invitations",
        "accept_invitation_by_id",
        { invitation_id: invitationId },
        accepted,
      );
    },
    myInvitations() {
      return run("invitations", "my_invitations", {}, (value) =>
        (Array.isArray(value) ? value.filter(isRecord) : []).map(
          invitationFrom,
        ),
      ).andThen((invitations) => readAllFields(invitationFields, invitations));
    },
    declineInvitationById(invitationId) {
      return run(
        "invitations",
        "decline_invitation_by_id",
        { invitation_id: invitationId },
        (value) => value === true,
      );
    },
  };
}
