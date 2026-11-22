import type { EveSessionAuth } from "./types.ts";

/**
 * Eve's `SkillScope` from `eve/experimental/extensions/custom-skills`, typed
 * structurally so this entry never imports eve.
 */
export interface EveSkillScope {
  readonly name: string;
  readonly key: string;
  readonly label: string;
  readonly shared: boolean;
  readonly readOnly?: boolean;
  readonly loadPrefix?: string;
  readonly metadata?: Readonly<Record<string, unknown>>;
}

/**
 * The part of eve's `SkillScopeContext` the resolver reads. eve 1.3.0 added
 * `turn` and `session.parent`.
 */
export interface EveSkillScopeContext {
  readonly session: {
    readonly id: string;
    readonly auth: {
      readonly current: EveSessionAuth | null;
      readonly initiator?: EveSessionAuth | null;
    };
    readonly parent?: {
      readonly sessionId: string;
      readonly rootSessionId: string;
    };
  };
  readonly turn?: { readonly id: string };
  readonly conversation?: { readonly space?: { readonly id: string } };
}

/** What `supabaseSkillScopes({ persona })` receives for each turn. */
export interface EveSkillPersonaContext {
  readonly tenantId: string;
  /** The caller's principal, `undefined` for an anonymous or runtime caller. */
  readonly principalId: string | undefined;
  readonly sessionId: string;
  /** Absent before a session's first turn. */
  readonly turnId: string | undefined;
  /** The session that delegated this one, such as a subagent's parent. */
  readonly parent:
    | { readonly sessionId: string; readonly rootSessionId: string }
    | undefined;
}

export interface SupabaseSkillScopesOptions {
  /**
   * The tenant-wide `organization` scope everyone in the tenant shares. It is
   * read-only unless the caller holds one of `writableBy` in the tenant (the
   * `roles` attribute `supabaseAuth` sets). `false` leaves it out. Defaults to
   * a read-only scope.
   */
  readonly organization?:
    | false
    | { readonly writableBy?: readonly string[]; readonly label?: string };
  /**
   * The `channel` scope of a shared conversation space (a Slack channel, a
   * group chat), partitioned by tenant. Defaults to `true`.
   */
  readonly channel?: boolean;
  /**
   * The persona this turn speaks as, read from state the app records per turn
   * or per parent session. A name adds a read-only `persona` scope shared by
   * the tenant; `undefined` adds none.
   */
  readonly persona?: (
    ctx: EveSkillPersonaContext,
  ) => string | undefined | Promise<string | undefined>;
}

/**
 * The resolver eve's `customSkills({ scopes })` calls before every model and
 * tool call.
 */
export type EveSkillScopeResolver = (
  ctx: EveSkillScopeContext,
) => Promise<readonly EveSkillScope[]>;

const text = (
  auth: EveSessionAuth | null | undefined,
  name: string,
): string | undefined => {
  const value = auth?.attributes[name];

  return typeof value === "string" && value !== "" ? value : undefined;
};

const list = (
  auth: EveSessionAuth | null | undefined,
  name: string,
): readonly string[] => {
  const value = auth?.attributes[name];

  if (value === undefined) {
    return [];
  }

  return typeof value === "string" ? [value] : value;
};

const isPerson = (auth: EveSessionAuth | null): auth is EveSessionAuth =>
  auth?.principalType === "user" && text(auth, "isAnonymous") !== "true";

/**
 * A scope resolver for eve's custom skills extension that keeps every skill
 * inside the caller's tenant: a `personal` scope per signed-in user, a
 * `persona` scope chosen per turn, a `channel` scope per shared space and an
 * `organization` scope for the tenant. Without a tenant the caller gets only
 * the personal and channel scopes, keyed as eve's defaults are.
 *
 * ```ts
 * export default customSkills({
 *   storage: supabaseDocumentBackend({ memory, scope: "skills" }),
 *   scopes: supabaseSkillScopes({
 *     organization: { writableBy: ["owner"] },
 *   }),
 * });
 * ```
 */
export function supabaseSkillScopes(
  options: SupabaseSkillScopesOptions = {},
): EveSkillScopeResolver {
  const organization = options.organization ?? {};

  return async (ctx) => {
    const auth = ctx.session.auth.current;
    const tenantId = text(auth, "tenantId");
    const prefix = tenantId === undefined ? "" : `tenant:${tenantId}:`;
    const scopes: EveSkillScope[] = [];

    if (isPerson(auth)) {
      scopes.push({
        name: "personal",
        key: `${prefix}user:${auth.principalId}`,
        label: "you",
        shared: false,
        ...(tenantId === undefined ? {} : { metadata: { tenantId } }),
      });
    }

    if (tenantId !== undefined && options.persona !== undefined) {
      const persona = await options.persona({
        tenantId,
        principalId: isPerson(auth) ? auth.principalId : undefined,
        sessionId: ctx.session.id,
        turnId: ctx.turn?.id,
        parent:
          ctx.session.parent === undefined
            ? undefined
            : {
                sessionId: ctx.session.parent.sessionId,
                rootSessionId: ctx.session.parent.rootSessionId,
              },
      });

      if (persona !== undefined && persona !== "") {
        scopes.push({
          name: "persona",
          key: `${prefix}persona:${persona}`,
          label: `the ${persona} persona`,
          shared: true,
          readOnly: true,
          loadPrefix: "persona",
          metadata: { tenantId, persona },
        });
      }
    }

    const space = ctx.conversation?.space;

    if (options.channel !== false && space !== undefined) {
      scopes.push({
        name: "channel",
        key: `${prefix}space:${space.id}`,
        label: "everyone in this channel",
        shared: true,
        loadPrefix: "channel",
        ...(tenantId === undefined ? {} : { metadata: { tenantId } }),
      });
    }

    if (organization !== false && tenantId !== undefined) {
      const roles = list(auth, "roles");

      const writable =
        isPerson(auth) &&
        (organization.writableBy ?? []).some((role) => roles.includes(role));

      scopes.push({
        name: "organization",
        key: `tenant:${tenantId}`,
        label: organization.label ?? "everyone in the organization",
        shared: true,
        ...(writable ? {} : { readOnly: true }),
        loadPrefix: "org",
        metadata: { tenantId },
      });
    }

    return scopes;
  };
}
