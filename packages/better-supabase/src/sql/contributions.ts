import type { BlockSqlContext } from "./context.ts";

/**
 * What a block adds to a generic block's SQL through `contributes`, keyed by
 * the generic block. The generic block reads the contributions of every
 * installed instance whose `uses` names it, so it never names its consumers.
 */
export interface BlockContributions {
  readonly approvals: ApprovalContribution;
  readonly "bulk-actions": BulkActionContribution;
  readonly pipelines: PipelineContribution;
  readonly "share-links": ShareLinkContribution;
  readonly subjects: SubjectContribution;
}

/** `BlockSql.contributes`: one function per generic block it adds to. */
export type BlockContributes = {
  readonly [K in keyof BlockContributions]?: (
    own: BlockSqlContext,
    target: BlockSqlContext,
  ) => readonly BlockContributions[K][];
};

/** SQL expressions for the approval request being decided. */
export interface ApprovalRequestSql {
  /** The request's subject id, as text. */
  readonly subjectId: string;
  /** The decision's comment. */
  readonly comment: string;
}

/** Requests of one subject type the contributing block files with approvals. */
export interface ApprovalContribution {
  readonly subject: string;
  /**
   * `declared`: whoever reads the organization's requests reads these.
   * `linked`: the contributing block decides them, so only the requester and
   * eligible approvers read them, they can't be delegated, and
   * `approval_settle` closes them.
   */
  readonly access: "declared" | "linked";
  /** Statements `approval_finalize` runs once a request is approved. */
  readonly approve: (request: ApprovalRequestSql) => string;
  /** Statements `decide_approval` runs when a request is rejected. */
  readonly reject?: (request: ApprovalRequestSql) => string;
  /** A boolean expression: whether the request can still be decided. */
  readonly approvable?: (request: ApprovalRequestSql) => string;
}

/** A bulk action the contributing block runs on one row. */
export interface BulkActionContribution {
  /** The action name callers pass, such as `tags.set`. */
  readonly name: string;
  /**
   * PL/pgSQL statements for one row, reading `bulk_row.tenant`,
   * `bulk_row.subject_type`, `bulk_row.subject_id` and `bulk_row.args`.
   */
  readonly run: string;
  /** Variables the statements declare, such as `v_tag uuid;`. */
  readonly declare?: string;
}

/** A record table of the contributing block that runs on pipelines. */
export interface PipelineContribution {
  /** The subject type, after the instance's entity names. */
  readonly type: string;
  /** The qualified table its records live in. */
  readonly table: string;
  /** The binding; an app's own `options.subjects` entry is merged over it. */
  readonly entry: Readonly<Record<string, unknown>>;
}

/** SQL expressions for the subject a new share link names. */
export interface ShareLinkSubjectSql {
  readonly id: string;
  readonly tenant: string;
}

/** A subject type the contributing block owns and share links can name. */
export interface ShareLinkContribution {
  readonly subject: string;
  /**
   * A boolean expression: the subject exists in the tenant, and the caller may
   * share it.
   */
  readonly exists: (subject: ShareLinkSubjectSql) => string;
  /** Statements share-links adds for this subject type, such as wrappers. */
  readonly sql?: string;
}

/** One section `record_summary` counts. */
export interface SummarySection {
  readonly name: string;
  /** The `from` clause; rows are aliased `x`. */
  readonly from: string;
  readonly subjectType: string;
  readonly subjectId: string;
  /** The row's time, for the unread check. */
  readonly latest: string;
  /** Extra conditions a counted row meets, such as not being deleted. */
  readonly live?: string;
  /**
   * When the caller last read the section, as a SQL expression; the `seen_at`
   * argument is the fallback.
   */
  readonly readAt?: string;
}

/** What the contributing block adds to the subject functions. */
export interface SubjectContribution {
  /** A section `record_summary` counts. */
  readonly summary?: SummarySection;
  /**
   * A `my_work` branch selecting `kind, subject_type, subject_id, ref, title,
   * at`; `my_work.tenant` filters by organization and `v_me` is the caller.
   */
  readonly work?: string;
  /** Statements the subjects block adds ahead of `my_work`. */
  readonly sql?: string;
}

/**
 * `contributions`, after checking that no two share a `key`: two instances of
 * one block that both contribute to the same generic block would.
 */
export function uniqueContributions<T>(
  generic: string,
  contributions: readonly T[],
  key: (contribution: T) => string | undefined,
): readonly T[] {
  const seen = new Set<string>();

  for (const contribution of contributions) {
    const name = key(contribution);

    if (name === undefined) {
      continue;
    }

    if (seen.has(name)) {
      throw new TypeError(
        `Two blocks contribute "${name}" to ${generic}. Point one instance's \`uses\` at another ${generic} instance.`,
      );
    }

    seen.add(name);
  }

  return contributions;
}
