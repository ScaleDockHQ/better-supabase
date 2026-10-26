import type { Issue } from "./issue.ts";

/** The part of a pg-delta `Action` the gate reads. */
export interface PlanActionLike {
  readonly sql: string;
  readonly verb: "create" | "alter" | "drop";
  readonly dataLoss: "none" | "destructive";
}

/** The part of a pg-delta `RenameCandidate` the gate reads. */
export interface RenameCandidateLike {
  readonly kind: string;
  readonly from: string;
  readonly to: string;
  readonly status: "unambiguous" | "ambiguous" | "nearMiss";
  readonly reason?: string;
}

/**
 * The part of a pg-delta `Plan` the gate reads; the real plan fits it
 * structurally.
 */
export interface PlanLike {
  readonly actions: readonly PlanActionLike[];
  readonly renameCandidates: readonly RenameCandidateLike[];
}

/** A rename the user recorded with `-- bsb: rename old -> new`. */
export interface RenameHint {
  readonly from: string;
  readonly to: string;
}

export interface GateOptions {
  /** Let destructive actions through (`--allow-data-loss`). */
  readonly allowDataLoss?: boolean;
  /** Renames recorded in the edit log; see `parseRenameHints`. */
  readonly hints?: readonly RenameHint[];
}

export interface PlanGate {
  /** Candidates a hint confirmed: apply these as renames. */
  readonly accepted: readonly RenameCandidateLike[];
  /** Unambiguous candidates nobody confirmed: ask the user. */
  readonly questions: readonly RenameCandidateLike[];
  /**
   * Ambiguous candidates and near misses: never guessed, they plan as drop and
   * create.
   */
  readonly unresolved: readonly RenameCandidateLike[];
  readonly destructive: readonly PlanActionLike[];
  /** `true` when a destructive action is present and `allowDataLoss` is off. */
  readonly blocked: boolean;
  readonly issues: readonly Issue[];
}

const HINT = /^--\s*bsb:\s*rename\s+(\S+)\s*->\s*(\S+)\s*$/gmu;

/** The `-- bsb: rename old -> new` lines of a migration or edit log. */
export function parseRenameHints(text: string): RenameHint[] {
  return [...text.matchAll(HINT)].flatMap((match) => {
    const [, from, to] = match;

    return from === undefined || to === undefined ? [] : [{ from, to }];
  });
}

function bare(name: string): string {
  return name.replaceAll('"', "").toLowerCase();
}

/** `id` names `name`, written as `table` or `schema.table`. */
function names(id: string, name: string): boolean {
  const wanted = bare(name);
  const have = bare(id);

  return (
    have === wanted ||
    have.endsWith(`.${wanted}`) ||
    have.endsWith(`:${wanted}`)
  );
}

function confirmed(
  candidate: RenameCandidateLike,
  hints: readonly RenameHint[],
): boolean {
  return hints.some(
    (hint) => names(candidate.from, hint.from) && names(candidate.to, hint.to),
  );
}

function planIssue(
  code: `plan_${string}`,
  severity: Issue["severity"],
  table: string,
  message: string,
): Issue {
  return { code, severity, source: "plan", path: "", table, message };
}

/**
 * Applies the rules of ADR 0106 to a plan: only a recorded rename or a
 * confirmed prompt becomes a rename, an ambiguous candidate never does, and a
 * destructive action is blocked unless data loss is allowed. Returns the
 * decisions and the findings as `Issue`s with `source: "plan"`.
 */
export function gatePlan(plan: PlanLike, options: GateOptions = {}): PlanGate {
  const hints = options.hints ?? [];
  const accepted: RenameCandidateLike[] = [];
  const questions: RenameCandidateLike[] = [];
  const unresolved: RenameCandidateLike[] = [];

  for (const candidate of plan.renameCandidates) {
    if (candidate.status !== "unambiguous") {
      unresolved.push(candidate);
    } else if (confirmed(candidate, hints)) {
      accepted.push(candidate);
    } else {
      questions.push(candidate);
    }
  }

  const destructive = plan.actions.filter(
    (action) => action.dataLoss === "destructive",
  );

  const blocked = destructive.length > 0 && options.allowDataLoss !== true;

  const issues: Issue[] = [
    ...questions.map((candidate) =>
      planIssue(
        "plan_rename_question",
        "warning",
        candidate.to,
        `Is ${candidate.from} renamed to ${candidate.to}? Record \`-- bsb: rename\` or it plans as drop and create.`,
      ),
    ),
    ...unresolved.map((candidate) =>
      planIssue(
        "plan_rename_unresolved",
        "info",
        candidate.to,
        `${candidate.from} to ${candidate.to} is ${candidate.status}${candidate.reason === undefined ? "" : `: ${candidate.reason}`}; it plans as drop and create.`,
      ),
    ),
    ...destructive.map((action) =>
      planIssue(
        "plan_data_loss",
        options.allowDataLoss === true ? "warning" : "error",
        "",
        `Destroys data: ${action.sql.split("\n")[0] ?? ""}`,
      ),
    ),
  ];

  return { accepted, questions, unresolved, destructive, blocked, issues };
}
