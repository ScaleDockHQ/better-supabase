/** The attributes the Supabase World's status trigger copies into `workflow_runs`. */
export const WORKFLOW_ATTRIBUTES = {
  tenant: "bs.tenant",
  actor: "bs.actor",
  key: "bs.key",
  /** The builder definition a run started from; its alerts match on it. */
  definition: "bs.definition",
  /** The builder version number a run started from. */
  version: "bs.version",
  /** The opaque ticket `bs.forContext` resolves into the context a step runs as. */
  ticket: "bs.ticket",
  /** The user an event or schedule start runs as (`runAs`). */
  publisher: "bs.publisher",
  /** The event actor or schedule creator behind a `runAs` start, for audit only. */
  trigger: "bs.trigger",
  /** The record a run belongs to, as `<type>/<id>`. */
  subject: "bs.subject",
  /** What a `runAs` run's steps run as: `user`, `service_principal`, `system` or `external`. */
  principalKind: "bs.principal_kind",
  /** The id of that principal, when it has one. */
  principal: "bs.principal",
  /** `test` for a builder test run; anything else records `live`. */
  mode: "bs.mode",
  /** The trigger node a builder run started at. */
  triggerNode: "bs.trigger_node",
} as const;

/**
 * The `bs.subject` value for a record: `<type>/<id>`. Throws a `TypeError`
 * for a type with a slash or an empty type or id, which the mirror can't
 * split back.
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
