/**
 * The attributes the Supabase World's status trigger copies into
 * `workflow_runs`.
 */
export const WORKFLOW_ATTRIBUTES = {
  tenant: "bsb.tenant",
  actor: "bsb.actor",
  key: "bsb.key",
  /** The builder definition a run started from; its alerts match on it. */
  definition: "bsb.definition",
  /** The builder version number a run started from. */
  version: "bsb.version",
  /**
   * The opaque ticket `bsb.forContext` resolves into the context a step runs
   * as.
   */
  ticket: "bsb.ticket",
  /** The user an event or schedule start runs as (`runAs`). */
  publisher: "bsb.publisher",
  /** The event actor or schedule creator behind a `runAs` start, for audit only. */
  trigger: "bsb.trigger",
  /** The record a run belongs to, as `<type>/<id>`. */
  subject: "bsb.subject",
  /**
   * What a `runAs` run's steps run as: `user`, `service_principal`, `system` or
   * `external`.
   */
  principalKind: "bsb.principal_kind",
  /** The id of that principal, when it has one. */
  principal: "bsb.principal",
  /** `test` for a builder test run; anything else records `live`. */
  mode: "bsb.mode",
  /** The trigger node a builder run started at. */
  triggerNode: "bsb.trigger_node",
} as const;

/**
 * The `bsb.subject` value for a record: `<type>/<id>`. Throws a `TypeError` for
 * a type with a slash or an empty type or id, which the mirror can't split
 * back.
 */
export function subjectAttribute(subject: {
  readonly type: string;
  readonly id: string;
}): string {
  if (
    subject.type === "" ||
    subject.type.includes("/") ||
    subject.type.length > 100 ||
    subject.id === "" ||
    subject.id.length > 200
  ) {
    throw new TypeError(
      "better-supabase: a workflow subject has a type of 1 to 100 characters without a slash and an id of 1 to 200",
    );
  }

  return `${subject.type}/${subject.id}`;
}
