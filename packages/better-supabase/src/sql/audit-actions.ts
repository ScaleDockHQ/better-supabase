/**
 * The outbox statement, written only when `live` is true. An empty event or no
 * guard is returned unchanged.
 */
export function liveStatement(event: string, live: string | undefined): string {
  if (event === "" || live === undefined) {
    return event;
  }

  return `if ${live} then\n    ${event.replaceAll("\n", "\n    ")}\n  end if;`;
}

/** An event a module writes to the outbox, as SQL expressions. */
export interface BlockSqlEmit {
  /** The event type, e.g. `organization.created`. */
  readonly type: string;
  /** A `jsonb` expression. */
  readonly payload: string;
  /** A `text` expression, e.g. `'organizations/' || new_organization`. */
  readonly subject?: string;
  /** The tenant id expression; it is cast to text. */
  readonly tenant?: string;
  /** A `text` idempotency key expression. */
  readonly key?: string;
  readonly row?: string;
}

/**
 * The categories module actions are audited under. An adopted log with its own
 * names maps them through `blocks.audit.options.values.category`.
 */
export const AUDIT_CATEGORIES = [
  "membership",
  "access",
  "security",
  "configuration",
  "billing",
  "data",
  "ai",
  "integration",
  "read",
] as const;

export type AuditCategory = (typeof AUDIT_CATEGORIES)[number];

/** How `record` writes an action to the audit log, as SQL expressions. */
export interface BlockSqlAudit {
  /** The audit category, mapped through `blocks.audit.options.values`. */
  readonly category: AuditCategory;
  /** What the action changed, e.g. `user` or `api_key`. */
  readonly targetType?: string;
  /** A `text` expression for the changed record's id. */
  readonly recordId?: string;
  /** A `text` expression people recognize the target by. */
  readonly targetLabel?: string;
  /** A `text` expression that says what happened. */
  readonly summary?: string;
  /** A `jsonb` expression; defaults to the event payload. */
  readonly metadata?: string;
  /** A `uuid` expression for the actor; defaults to the caller. */
  readonly actor?: string;
  /**
   * A `uuid` expression for the support session the action belongs to. Defaults
   * to the session in the caller's `act` claim, which wins when set.
   */
  readonly supportSession?: string;
  /**
   * A `uuid` expression for the admin acting as the user; defaults to
   * `act.sub`.
   */
  readonly impersonatedBy?: string;
  /**
   * A `text` expression for why the admin acts as the user; defaults to
   * `act.reason`.
   */
  readonly impersonationReason?: string;
  /**
   * A `text` expression for the actor kind, for the service role only (others
   * get the kind their token shows). Import runs write `'integration'`.
   */
  readonly actorKind?: string;
  /** A `text` expression that groups entries, e.g. `'import:' || run_id`. */
  readonly correlationId?: string;
}

/**
 * An action a module records once: the outbox gets it as an event and the audit
 * log as an entry, each when its module is installed.
 */
export interface BlockSqlAction extends BlockSqlEmit {
  /**
   * How the action is audited, or `false` for an event that is not an audited
   * action, such as a chat message or a run status.
   */
  readonly audit: BlockSqlAudit | false;
  /**
   * A boolean SQL expression. The outbox event is written only when it is true.
   * The audit entry is written either way, so a template edit stays audited.
   * ADR 0244.
   */
  readonly live?: string;
}
