import type { RelationKindOptions } from "../blocks/relations/options.ts";
import type { BlockSqlContext } from "./context.ts";

/**
 * What a block adds to a generic block's SQL through `contributes`, keyed by
 * the generic block. The generic block reads the contributions of every
 * installed instance whose `uses` names it, so it never names its consumers.
 */
export interface BlockContributions {
  readonly "access-requests": AccessGrantContribution;
  readonly accounting: AccountingContribution;
  readonly acknowledgements: AcknowledgementContribution;
  readonly approvals: ApprovalContribution;
  readonly bulk: BulkActionContribution;
  readonly imports: ImportTargetContribution;
  readonly numbering: NumberingContribution;
  readonly pipelines: PipelineContribution;
  readonly relations: RelationContribution;
  readonly "share-links": ShareLinkContribution;
  readonly "state-machine": StateMachineContribution;
  readonly subjects: SubjectContribution;
}

/** `BlockSql.contributes`: one function per generic block it adds to. */
export type BlockContributes = {
  readonly [K in keyof BlockContributions]?: (
    own: BlockSqlContext,
    target: BlockSqlContext,
  ) => readonly BlockContributions[K][];
};

/**
 * A kind of document the contributing block books in the accounting block.
 * `accounting_post_source` calls `lines` with the document's id and books what
 * it returns once per document.
 */
export interface AccountingContribution {
  /** The source type entries carry, such as `invoice`. */
  readonly source: string;
  /** The journal type the entry goes to unless the document names one. */
  readonly journal: "sales" | "purchase" | "bank" | "cash" | "general";
  /**
   * The qualified function `(source_id text) returns jsonb` that describes the
   * entry: `{ organizationId, entryDate, currency, reference, memo, journal?,
   * lines: [{ role | accountCode, debit | credit, currency?, taxRateBps? |
   * taxCode?, partyId?, dimensions?, description? }] }`, with amounts in the
   * document's currency, or `null` when there is nothing to book.
   */
  readonly lines: string;
}

/**
 * A subject type of the contributing block whose current version is a column on
 * its row, for when the app doesn't set
 * `blocks.acknowledgements.on.<type>.versionColumn` itself.
 */
export interface AcknowledgementContribution {
  /** The subject type, after the instance's entity names. */
  readonly subject: string;
  /** The column that holds the current version's id (a `versions` row). */
  readonly versionColumn: string;
  /**
   * The record's table, for when neither `on` nor `config.subjects` names the
   * type: `{ table, idType?, tenant?, permission? }` as in `on.<type>`.
   */
  readonly record?: {
    readonly table: string;
    readonly idType?: string;
    readonly tenant?: string;
    readonly permission?: string;
  };
}

/**
 * The `accessGrant` contribution: how a record access request on `subject`
 * grants access, instead of a `subject_members` row. `grant` is the qualified
 * name of a function `(subject_id text, user_id uuid, action text, ends_at
 * timestamptz)`, such as `drive_grant_access`. Access requests call it when a
 * request is approved or an emergency opens, and again with `ends_at = now()`
 * when the access ends early; it grants until `ends_at` and replaces the grant
 * it made before for the same user.
 */
export interface AccessGrantContribution {
  /** The subject type, which also declares `subjects.<type>.team`. */
  readonly subject: string;
  readonly grant: string;
  /**
   * A function `(subject_id text) returns uuid[]`: who approves a request on a
   * record that has no team lead, before the holders of `subjects.manage`.
   */
  readonly approvers?: string;
}

/** SQL expressions for the approval request being decided. */
export interface ApprovalRequestSql {
  /** The request's id. */
  readonly id: string;
  /** The request's subject id, as text. */
  readonly subjectId: string;
  /** The decision's comment. */
  readonly comment: string;
  /** The user whose decision this is, as uuid. */
  readonly approver: string;
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

/**
 * A kind of record the contributing block takes in imports (ADR 0141).
 * \`import_upsert_batch\` calls \`write\` for each item of \`entity\` whose
 * content is new or changed, and maps the key to the subjects it returns.
 */
export interface ImportTargetContribution {
  /** The entity name callers pass to \`import_upsert_batch\`, such as \`party\`. */
  readonly entity: string;
  /** The subject type of the primary row the write creates. */
  readonly subjectType: string;
  /**
   * The qualified function \`(run uuid, item jsonb, subject_id text) returns
   * jsonb\`. \`item\` is \`{ key, scope, data, refs, tenant }\`; \`subject_id\`
   * is the primary subject of an earlier import, or \`null\` for an insert. It
   * writes one row (or several) and returns \`{ subjectId, role?, subjectType?,
   * updatedAt? }\` for each subject it touched, as an array or a single object;
   * \`role\` defaults to \`primary\`. It raises with a hint to report the item
   * as an error and leave the run going.
   */
  readonly write: string;
  /**
   * The qualified function \`(subject_id text) returns timestamptz\` that reads
   * the row's last change. Without it a changed hash always overwrites. With
   * it, a row changed after the last import is \`conflicted\` and left alone.
   */
  readonly updatedAt?: string;
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

/**
 * A number sequence the contributing block draws from, for when the app doesn't
 * configure `blocks.numbering.options.entities.<entity>` itself.
 */
export interface NumberingContribution {
  /** The entity name, after the instance's entity names. */
  readonly entity: string;
  /** The default entry: `{ period, format }` and the other entity keys. */
  readonly entry: Readonly<Record<string, unknown>>;
}

/** A record table of the contributing block that runs on pipelines. */
export interface PipelineContribution {
  /** The subject type, after the instance's entity names. */
  readonly type: string;
  /** The qualified table its records live in. */
  readonly table: string;
  /** Its tenant column, unquoted, as the block names it. */
  readonly tenant: string;
  /** The binding; an app's own `on` entry is merged over it. */
  readonly entry: Readonly<Record<string, unknown>>;
}

/**
 * A kind of link the contributing block needs, for when the app doesn't
 * configure `blocks.relations.options.kinds.<kind>` itself. Name subject types
 * in `types` after the instance's entity names.
 */
export interface RelationContribution extends RelationKindOptions {
  readonly kind: string;
  /**
   * A boolean expression over the link's `data` (a jsonb expression) that every
   * link of this kind must pass, or `link` raises `RELATION_DATA_INVALID`. An
   * app kind of the same name drops it.
   */
  readonly data?: (data: string) => string;
}

/** SQL expressions for the subject a new share link names. */
export interface ShareLinkSubjectSql {
  readonly id: string;
  readonly tenant: string;
  /** The link's role, `view` when the caller names none. */
  readonly role: string;
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
  /**
   * One live link per record and creator: a new link revokes the creator's
   * earlier ones, such as a feed whose old address should stop working.
   */
  readonly single?: boolean;
  /**
   * The roles a link to this subject type may carry. `create_share_link`
   * refuses any other with `SHARE_LINK_ROLE_INVALID`. Default: `["view"]`.
   */
  readonly roles?: readonly string[];
}

/**
 * A status machine on a table of the contributing block, for when the app
 * doesn't configure `blocks.state-machine.options.machines.<name>` itself. The
 * table must render before the state-machine block.
 */
export interface StateMachineContribution {
  /** The machine name: the subject type its approvals and history use. */
  readonly name: string;
  /** The machine entry: `table`, `column`, `transitions` and the other keys. */
  readonly entry: Readonly<Record<string, unknown>>;
  /**
   * The status may stay null: an insert keeps it null, and a null status may
   * only move to `initial`. For tables where only some rows run the machine.
   */
  readonly optional?: boolean;
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
