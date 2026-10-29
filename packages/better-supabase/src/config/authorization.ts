import type { ActiveTenantSource, DisabledRow } from "./blocks.ts";

/**
 * SQL expression templates the SQL modules and the access policies call.
 * `{permission}` is a text expression (a literal or a parameter), `{user}` a
 * uuid expression, `{tenant}` an expression of the tenant id type, `{role}` a
 * text expression and `{roles}` a `text[]` of the roles being assigned
 * (`array[{role}]` for one role, the whole set with
 * `blocks.memberships.options.roles.many`). `{scope}` is the scope's name
 * unquoted, so it can be part of a function name
 * (`app.ids_{scope}({permission})`); write `'{scope}'` to pass it as text.
 */
export interface AuthorizationFunctions {
  /**
   * The ids of the `{scope}` instances where the caller holds `{permission}`,
   * as a set: it is used as `select t.id::text from <template> as t(id)`.
   */
  readonly idsWith: string;
  /** Whether the caller holds `{permission}` platform-wide. */
  readonly isPlatform: string;
  /** `idsWith` for `{user}`, so `can_user` answers for another user. */
  readonly idsWithFor?: string;
  /** `isPlatform` for `{user}`. */
  readonly isPlatformFor?: string;
  /** The ids of the `{scope}` instances the caller is a member of, as a set. */
  readonly memberIds?: string;
  /**
   * `memberIds` for `{user}`, which the access token hook calls as
   * `supabase_auth_admin`.
   */
  readonly memberIdsFor?: string;
  /**
   * The team ids `{user}` belongs to, as a set of the team id type: it is used
   * as `select t.id from <template> as t(id)`. Under the provider model the
   * teams module's `team_ids_of()`, and the team sharing in `saved-views` and
   * `collections`, call it instead of reading `team_members`.
   */
  readonly teamIdsOf?: string;
  /**
   * Whether the caller may assign `{role}` (or every one of `{roles}`) in
   * `{tenant}`.
   */
  readonly canAssign?: string;
  /**
   * Whether `{user}` may assign `{role}` (or every one of `{roles}`) in
   * `{tenant}`.
   */
  readonly canAssignFor?: string;
  /**
   * The permission keys `{user}` holds in `{tenant}`, as a `text[]`. It fills
   * `member_permissions` and the `permissions` claim; without it both are
   * empty.
   */
  readonly permissionsFor?: string;
  /**
   * Whether the caller may decide the tool call `{tool}` (text) waits on in
   * `{tenant}`. Without it only the chat's owner and the service role decide.
   *
   * @deprecated Use `isApprover`, which every module that waits for an
   * approval reads. `canApprove` is read for tool calls only when
   * `isApprover` is unset.
   */
  readonly canApprove?: string;
  /**
   * Whether the caller may approve the request `{subject}` (text) of kind
   * `{kind}` (a text literal: `'ai-tool'` with the tool name as `{subject}`,
   * `'support-session'` with the request id, or the app's own kind) in
   * `{tenant}`. `{requester}` is the uuid of the user who asked (the approval's
   * `requested_by`, the support admin, the chat's owner), or `null`; a provider
   * that resolves out-of-office covers reads it to refuse a cover by the
   * requester's own delegator. `{approvers}` is a jsonb value with the
   * approvers the request waits on now: the approvals block's current step
   * `approvers` with its `required` count, or `escalateTo` once escalated, and
   * `null` elsewhere. It replaces each module's own eligibility check; the
   * requester is refused before it runs. Without it a module falls back to its
   * default approver (the chat's owner, a platform permission).
   */
  readonly isApprover?: string;
  /**
   * The user ids that hold `{permission}` on `{tenant}`, as a set: it is used
   * as `select u from <template> as t(u)`. A notification's `permission`
   * audience calls it. Without it, naming `permission` is refused.
   */
  readonly holdersOf?: string;
  /**
   * Whether the caller's session may write. No placeholders. Write functions
   * and write policies call it instead of the built-in act check.
   */
  readonly actorMayWrite?: string;
  /**
   * Whether the caller holds `{permission}` on the instance `{id}` (text) of
   * `{resource}` in `{tenant}`, at `{scope}`. A realtime topic that declares a
   * `permission` calls it for the instance in its topic name.
   */
  readonly permitted?: string;
  /**
   * The ids of the rows of `{resource}` the caller holds `{permission}` on, as
   * a set of text: it is used as `select r.id from <template> as r(id)`.
   * `{resource}` is a resource name as the provider spells it in SQL (such as
   * `file_node`), unquoted, so it can be part of a function name; `{ids}` is a
   * `text[]` of the candidate ids, which a provider may use to limit the work.
   * `can_subject` calls it for a `config.subjects.<type>.permissions.<action>`
   * entry with `rows`.
   */
  readonly rowsWith?: string;
  /**
   * `rowsWith` for `{user}`, so `can_subject_for` answers per-row grants for
   * another user. Without it those grants count for the caller only.
   */
  readonly rowsWithFor?: string;
  /**
   * The records the caller may reach as a guest for `{action}` (`read`,
   * `comment` or `upload`), as a set of `(tenant text, subject_type text,
   * subject_id text)`: it is used as `select g.tenant, g.subject_type,
   * g.subject_id from <template> as g(tenant, subject_type, subject_id)`.
   * `ctx.scope.guest` calls it, so comments, attachments, invoices and bookings
   * let a provider's external users in (ADR 0070). With the `guests` block
   * installed its grants are added to these.
   */
  readonly portalSubjects?: string;
  /**
   * The parties the caller acts for as a guest, as a set of `(tenant text,
   * party_type text, party_id text)`. No placeholders. `ctx.scope.guestParty`
   * calls it for portal reads such as a customer's own invoices.
   */
  readonly portalParties?: string;
}

/** One scope the provider decides permissions in, such as `organization`. */
export interface AuthorizationScope {
  /** Lower case letters, digits and `_`, starting with a letter. */
  readonly name: string;
  /**
   * The Postgres type of the scope's ids: `uuid`, `text`, `bigint` or
   * `integer`.
   */
  readonly idType?: string;
  /** The scope this one sits in; the root scope has none. */
  readonly parent?: string;
}

/** A function the templates call, which must exist and be executable by `role`. */
export interface AuthorizationRequirement {
  /** `schema.name`. */
  readonly function: string;
  /** The argument types, such as `text` or `uuid, text`. */
  readonly args?: string;
  readonly role: string;
}

/** A permission key the provider defines. */
export interface AuthorizationPermission {
  readonly key: string;
  /**
   * `true` when the SQL functions answer for the key completely. A key with row
   * conditions they don't check is `false`, and policies refuse it. Unset means
   * unknown, which counts as `false`.
   */
  readonly sqlComplete?: boolean;
  /** The scopes it can be granted at. */
  readonly scopes?: readonly string[];
}

/**
 * One named operation: what workflow builder nodes, MCP tools, AI tools and
 * inbox commands with that name need. The provider supplies the table;
 * `blocks.<module>.permissions` still renames a module's own keys.
 */
export interface AuthorizationOperation {
  /** The permission key the operation needs. */
  readonly permission: string;
  readonly meta?: {
    /** `low`, `medium` or `high`; a `high` operation can ask for approval. */
    readonly risk?: "low" | "medium" | "high";
    /** What it changes: `read`, `write`, `delete`, `external`. */
    readonly effects?: readonly ("read" | "write" | "delete" | "external")[];
    readonly title?: string;
  };
}

/** A table of memberships the provider reads. */
export interface AuthorizationMembership {
  /** `schema.table`. */
  readonly table: string;
  readonly userColumn: string;
  /** The scope column, or the scope every row is in. */
  readonly scope: { readonly column: string } | { readonly value: string };
  readonly idColumn: string;
  /**
   * `schema.table` of the membership's role set, one row per `(scope id, user,
   * role)`, when a member can hold several roles. better-supabase's own is
   * `better_supabase.membership_roles`
   * (`blocks.memberships.options.roles.many`).
   */
  readonly rolesTable?: string;
}

/** A membership table whose role column points into a roles table. */
export interface AuthorizationRoleSource {
  /** `schema.table` of the memberships. */
  readonly table: string;
  readonly role: {
    readonly column: string;
    readonly through: {
      /** `schema.table` of the roles. */
      readonly table: string;
      readonly id: string;
      readonly column: string;
    };
  };
}

/** The access token hook the provider generates. */
export interface AuthorizationTokenHook {
  /** `schema.name`. */
  readonly function: string;
  /** The claim it writes the active tenant id to. */
  readonly tenantClaim?: string;
  /**
   * Where it reads the active organization from: the `auth.tenant.claim` key in
   * `app_metadata` (`"claim"`), a profile column, or the request
   * (`"resolver"`). Doctor BS409 warns when `switch_organization` writes it
   * somewhere else (`blocks.permissions.activeTenant`).
   */
  readonly activeOrganizationFrom?: ActiveTenantSource;
  /**
   * Claims it writes itself, which a second writer would contradict. With
   * `permissions` here, better-supabase's hook template leaves the claim to
   * it.
   */
  readonly ownedClaims: readonly string[];
  /**
   * The claim it sets to `true` when it left permission keys out of the
   * `permissions` claim. Readers (`permissionsOf`, `isTruncated`,
   * `permissionsAuthorizer`) then ask the database. Defaults to
   * `budget.truncatedClaim`, then `<permissions claim>_truncated`.
   */
  readonly truncatedClaim?: string;
  /**
   * Claims it fills from other functions, such as `features` from
   * `better_supabase.feature_claims`.
   */
  readonly registeredClaims?: readonly {
    readonly name: string;
    /** `schema.name`. */
    readonly function: string;
  }[];
  /** A byte budget over some claims, which doctor `--as` measures (BS405). */
  readonly budget?: {
    readonly claims: readonly string[];
    readonly bytes: number;
    /**
     * A claim the hook sets to `true` when it dropped entries to stay within
     * the budget.
     */
    readonly truncatedClaim?: string;
  };
  /**
   * Comment lines the provider's generated files contain, so doctor recognises
   * them.
   */
  readonly markers?: {
    /** In the file that defines the hook. */
    readonly hook?: string;
    /** In the migration that grants the hook's functions. */
    readonly grants?: string;
  };
  /** The command that writes the hook's grants, for BS404. */
  readonly grantsCommand?: string;
}

/** Where a provider keeps the authorization versions. */
export interface AuthorizationVersions {
  /**
   * `schema.name` of a `(uuid) returns bigint` function: the user's current
   * version, 0 before the first change. It may be closed to client roles;
   * better-supabase calls it from a security definer function.
   */
  readonly function: string;
}

/**
 * An authorization system the SQL modules, the policies and doctor delegate to.
 * It is plain data, usually built from the provider's own output files.
 */
export interface AuthorizationProvider {
  readonly apiVersion: 1;
  /** The provider's name, for messages. */
  readonly name: string;
  readonly scopes: readonly AuthorizationScope[];
  /** The scope tenants are. */
  readonly tenantScope: string;
  readonly functions: AuthorizationFunctions;
  readonly requires?: readonly AuthorizationRequirement[];
  readonly permissions?: readonly AuthorizationPermission[];
  /**
   * Operations by name (`workflow.node.http`, `mcp.tool.search_posts`,
   * `ai.tool.send_email`, `inbox.command.assign`). A module looks an operation
   * up here first and uses its own default permission otherwise.
   */
  readonly operations?: Readonly<Record<string, AuthorizationOperation>>;
  readonly memberships?: readonly AuthorizationMembership[];
  /** Rows that say whether a user or a tenant is active. */
  readonly suspension?: {
    readonly user?: DisabledRow;
    readonly tenant?: DisabledRow;
  };
  readonly roleSources?: readonly AuthorizationRoleSource[];
  /** `schema.table.column` of every column that decides access (BS213). */
  readonly decidingColumns?: readonly string[];
  readonly tokenHook?: AuthorizationTokenHook;
  /**
   * The provider keeps each user's authorization version (the `authz_ver`
   * claim). `blocks.sessions.options.authzVersions` then creates no version
   * table of its own: `better_supabase.caller_authz_version()` and the
   * bootstrap wrappers read this function. The provider also broadcasts `{
   * user_id, version }` as `changed` on `authz:<uid>` and ships the
   * `realtime.messages` policy that lets the user receive it.
   */
  readonly versions?: AuthorizationVersions;
  /** What a delegated token (an OAuth client or agent) may use. */
  readonly delegation?: {
    /**
     * OAuth scope to the permission keys it grants (RFC 9396 details stay with
     * the app). `blocks.permissions.scopes` is merged over it.
     */
    readonly scopes?: Readonly<Record<string, readonly string[]>>;
  };
  /** How `canApprove` decisions are made. */
  readonly approvals?: {
    /** The user who asked for the tool call can't approve it. Default `false`. */
    readonly distinctApprover?: boolean;
  };
  /** What the provider found wrong while building this, for doctor. */
  readonly problems?: readonly string[];
}

/**
 * The error for a provider built for another API version, or `undefined` for
 * version 1.
 */
export function providerApiProblem(provider: {
  readonly name?: unknown;
  readonly apiVersion?: unknown;
}): string | undefined {
  const version = provider.apiVersion;

  if (version === 1) {
    return undefined;
  }

  const name = typeof provider.name === "string" ? provider.name : "provider";

  return `authorization "${name}" targets authorization provider API ${String(version)}; this better-supabase supports 1. Upgrade better-supabase or use a release of the provider for API 1.`;
}
