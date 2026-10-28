import type { AuthState } from "../../auth/resolve.ts";
import type { RequestContext } from "../plugin.ts";

/**
 * An email address or chat user, as a bot or a mail webhook sees it. The value
 * is what the platform reports; it names no one until an identity link maps it
 * to a user or a contact.
 */
export interface IdentityRef {
  readonly kind: "email" | "chat";
  /** `slack`, `teams`, `whatsapp`, an email provider; unset for a plain address. */
  readonly provider?: string;
  /** The address (lower case) or the platform's user id. */
  readonly value: string;
  /** The platform workspace, such as a Slack team id. */
  readonly workspace?: string;
}

/** Where an identity link points: an app user or a contact the app stores. */
export type IdentityTarget =
  | { readonly kind: "user"; readonly userId: string }
  | { readonly kind: "contact"; readonly contactId: string };

/**
 * Looks up the verified link for an identity. `null` for an identity no
 * signed-in link flow or verified address created; the caller then treats the
 * author as anonymous.
 */
export type PrincipalByIdentity = (
  identity: IdentityRef,
) => IdentityTarget | null | Promise<IdentityTarget | null>;

/** The fields of an event a subscriber check reads. */
export interface SubscriberEvent {
  readonly type: string;
  readonly tenant: string | null;
  /** The user who caused the event, or `null` for service work. */
  readonly actorId: string | null;
  readonly payload: unknown;
  /** The event's subject, such as `invoices/123`, when it has one. */
  readonly subject?: string | null;
}

/**
 * A subscription a fan-out may deliver to. `principal` is the user who owns it,
 * or the id of the service principal an organization-owned subscription runs as
 * (`kind: "secret"`).
 */
export interface Subscriber {
  readonly principal: string;
  readonly kind?: "user" | "service";
}

/**
 * Narrows a fan-out to the subscribers that may read the event: webhook
 * endpoints, outbox consumers, realtime members and notification recipients. It
 * returns a subset of `subscribers`; a subscriber it leaves out gets nothing,
 * and a throw or rejection delivers to no one.
 */
export type SubscriberPolicy = <S extends Subscriber>(
  event: SubscriberEvent,
  subscribers: readonly S[],
) => readonly S[] | Promise<readonly S[]>;

/** A request that waits for someone other than the requester to approve it. */
export interface ApprovalRequestRef {
  /** `ai-tool` (an AI tool call), `support-session`, or the app's own kind. */
  readonly kind: string;
  /** The tool name for `ai-tool`, the request id for `support-session`. */
  readonly subject: string;
  readonly tenant?: string;
  /** The user who asked; never their own approver. */
  readonly requester?: string;
}

/** The signed-in user who would approve, with their verified claims. */
export interface Approver {
  readonly userId: string;
  readonly claims: Readonly<Record<string, unknown>>;
}

/**
 * Whether `approver` may decide `request`. The SQL side is the `isApprover`
 * template of the authorization provider; this is the same decision for server
 * code. A throw counts as `false`, and better-supabase refuses the requester
 * before it asks.
 */
export type ApproverOf = (
  approver: Approver,
  request: ApprovalRequestRef,
) => boolean | Promise<boolean>;

/** What `mayPublish` and `runAs` get about a published automation. */
export interface AutomationRef {
  /** The user who published it, or `null` for an organization-owned automation. */
  readonly publisher: string | null;
  readonly tenant: string | null;
  /** The permissions its nodes need, as stored at publish. */
  readonly permissions: readonly string[];
}

/** How a provider decides published automations (workflow builder versions). */
export interface AutomationHooks {
  /** Whether the publisher may publish a version whose nodes need `permissions`. */
  readonly mayPublish?: (
    automation: AutomationRef & {
      readonly claims: Readonly<Record<string, unknown>>;
    },
  ) => boolean | Promise<boolean>;
  /**
   * The claims a step of a published version runs with: the publisher's current
   * claims narrowed to `permissions`, or the service principal's for an
   * organization-owned automation. `null` when the publisher is gone, suspended
   * or no longer holds a stored permission; the step then fails and never falls
   * back to the service role.
   *
   * Put the cap under `PERMISSION_CAP_CLAIM` (`bsb_permission_cap`, from
   * `better-supabase/server`): `cap_allows` refuses every key outside it. 0.15
   * still reads the 0.14 name, `bs_permission_cap`, and warns once.
   */
  readonly runAs?: (
    automation: AutomationRef,
  ) =>
    | Readonly<Record<string, unknown>>
    | null
    | Promise<Readonly<Record<string, unknown>> | null>;
}

/**
 * Turns an opaque run ticket back into the context a job or a workflow step
 * runs as. `null` or a throw refuses the ticket (expired, revoked, or for a
 * principal that is gone), and the run fails instead of running as anyone else.
 * The ticket is stored in plain text as a run attribute, so it is an id the
 * provider looks up, never a bearer secret.
 */
export type TicketSubject = (
  ticket: string,
) => RequestContext | null | Promise<RequestContext | null>;

/**
 * A delegated token, as `forContext` sees it: an OAuth client or agent acting
 * for a user.
 */
export interface DelegationRef {
  readonly userId: string;
  readonly tenant?: string;
  /** The OAuth client, when the token has a `client_id`. */
  readonly clientId?: string;
  /** The scopes the user granted, split on spaces. */
  readonly scopes: readonly string[];
  /** RFC 9396 `authorization_details`, when the token has them. */
  readonly authorizationDetails?: readonly {
    readonly type: string;
    readonly [field: string]: unknown;
  }[];
}

/**
 * The permission keys a delegated token may use, for scopes the provider maps
 * at runtime (`authorization.delegation.scopes` is the static form in SQL).
 * `forContext` caps the work to them, narrowed by its own `permissions`; a
 * throw grants nothing.
 */
export type DelegationPermissions = (
  delegation: DelegationRef,
) => readonly string[] | Promise<readonly string[]>;

/** A button a chat user pressed on a message the app sent. */
export interface ChatAction {
  /** The action id the card declared, such as `approve`. */
  readonly id: string;
  readonly value?: string;
  /** The chat user, as the platform reports them. */
  readonly author: IdentityRef;
}

/**
 * Decides a chat action for its linked author: `undefined` when the provider
 * does not handle the action. An approval button is decided here, through the
 * provider; an unlinked author is refused.
 */
export type ChatActionHook = (
  action: ChatAction,
  author: IdentityTarget | null,
) =>
  | { readonly allowed: boolean; readonly userId?: string }
  | undefined
  | Promise<
      { readonly allowed: boolean; readonly userId?: string } | undefined
    >;

/** A support session start the `authorize` hook decides. */
export interface SupportAuthorizeInput {
  readonly admin: Extract<AuthState, { kind: "user" }>;
  readonly targetUserId: string;
  /** Never empty: a start without a reason is refused before `authorize` runs. */
  readonly reason: string;
  readonly readOnly: boolean;
  readonly tenant?: string;
  readonly metadata: Readonly<Record<string, unknown>>;
}

/**
 * `true` allows a support start that still needs a second approver unless
 * approval is off; `{ approvedBy }` allows it and names the distinct approver
 * the provider checked. `false`, a throw and an `approvedBy` equal to the admin
 * refuse it.
 */
export type SupportDecision = boolean | { readonly approvedBy: string };

/** Decides a support session start. */
export type SupportAuthorize = (
  input: SupportAuthorizeInput,
) => SupportDecision | Promise<SupportDecision>;

/**
 * The runtime half of an authorization provider (`apiVersion: 1`). The
 * `authorization` config key is plain data for SQL; these hooks decide the same
 * things in server code, so one provider can own automations, support sessions,
 * delivery, identity links, chat actions, approvals and delegated tokens end to
 * end. Every hook is optional, and a slot passed to a block directly wins over
 * the hook.
 */
export interface AuthorizationHooks {
  readonly apiVersion: 1;
  /** The provider's name, for messages. */
  readonly name: string;
  readonly automation?: AutomationHooks;
  readonly support?: { readonly authorize: SupportAuthorize };
  readonly delivery?: {
    /** Webhook endpoints, outbox consumers and realtime members. */
    readonly subscribers?: SubscriberPolicy;
    /** Notification recipients. */
    readonly audience?: SubscriberPolicy;
  };
  readonly identities?: { readonly principalByIdentity: PrincipalByIdentity };
  readonly chat?: { readonly onAction?: ChatActionHook };
  readonly approverOf?: ApproverOf;
  readonly tickets?: { readonly subject: TicketSubject };
  readonly delegation?: { readonly permissions: DelegationPermissions };
  /**
   * The provider's own cache tags for a user, such as the tag of its permission
   * snapshot. `bsb.cached()` entries carry them, and `evictSession`, sign-out
   * and `refreshSessionCache` clear them with the session tags.
   */
  readonly sessionTags?: (userId: string) => readonly string[];
}

/** Types `hooks` and freezes it; better-supabase never mutates a provider. */
export function defineAuthorizationHooks<const H extends AuthorizationHooks>(
  hooks: H,
): H {
  return Object.freeze(hooks);
}

/** The error for hooks built for another API version, or `undefined` for version 1. */
export function hooksApiProblem(hooks: {
  readonly name?: unknown;
  readonly apiVersion?: unknown;
}): string | undefined {
  if (hooks.apiVersion === 1) {
    return undefined;
  }

  const name = typeof hooks.name === "string" ? hooks.name : "provider";

  return `authorization hooks "${name}" target API ${String(hooks.apiVersion)}; this better-supabase supports 1.`;
}
