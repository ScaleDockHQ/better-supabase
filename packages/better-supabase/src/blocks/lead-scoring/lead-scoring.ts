import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { RuleFieldCatalog } from "../rules/fields.ts";
import type { ComputedScore } from "../scores/scores.ts";
import type { BlockOptions, SubjectRef } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { defineRuleFields } from "../rules/fields.ts";
import { computedScoreOf } from "../scores/scores.ts";
import { applyTemporal, blockCall, isRecord } from "../shared.ts";

export interface LeadScoring {
  /** Scores one person or company under its lead model now. */
  score(subject: SubjectRef): AsyncResult<ComputedScore>;
  /**
   * The values the lead model reads for a record: its columns, `segments`,
   * `mail` and `enrichment`. `null` when there is no such record.
   */
  fields(
    subject: SubjectRef,
  ): AsyncResult<Readonly<Record<string, unknown>> | null>;
  /**
   * Scores up to `limit` records that changed, or weren't scored for
   * `rescoreAfterHours`, as the service role. Call it from a cron route.
   * Returns how many it scored.
   */
  scoreDue(options?: { readonly limit?: number }): AsyncResult<number>;
}

export interface LeadScoringOptions extends BlockOptions {
  readonly hooks?: NoInfer<BlockHooks<LeadScoring>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

/**
 * The fields lead scoring adds to a record, for a lead model's rules. Sync it
 * with `createRulesAdmin(...).syncFields(leadRuleFields("person"))`, next to
 * the record's own columns.
 */
export function leadRuleFields<const S extends string>(
  subjectType: S,
): RuleFieldCatalog<S> {
  return defineRuleFields(subjectType, {
    segments: {
      type: "multiselect",
      label: "Segments",
      description: "The ids of the segments the record is in.",
    },
    "mail.sent": { type: "number", label: "Emails sent" },
    "mail.opened": { type: "number", label: "Emails opened" },
    "mail.clicked": { type: "number", label: "Emails clicked" },
    "mail.replied": { type: "number", label: "Replies" },
    "mail.lastSentAt": { type: "date", label: "Last email sent" },
    "mail.lastRepliedAt": { type: "date", label: "Last reply" },
    "enrichment.status": {
      type: "select",
      label: "Enrichment",
      options: ["matched", "not_found"],
    },
  });
}

/**
 * Scores people, and optionally companies, under a score model whose rules read
 * the record, its segments, its mail and its enrichment.
 */
export function createLeadScoring(options: LeadScoringOptions): LeadScoring {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const service = blockCall(
    options.service ?? options.transport,
    options.schema,
    options.mappers,
  );

  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const subjectArgs = (organizationId: string, subject: SubjectRef) => ({
    tenant: organizationId,
    subject_type: subject.type,
    subject_id: subject.id,
  });

  const client: LeadScoring = {
    score: (subject) =>
      tenant().andThen((organizationId) =>
        call("score_lead", subjectArgs(organizationId, subject), (value) =>
          computedScoreOf(value, "score_lead"),
        ),
      ),
    fields: (subject) =>
      tenant().andThen((organizationId) =>
        call("lead_fields", subjectArgs(organizationId, subject), (value) =>
          isRecord(value) ? value : null,
        ),
      ),
    scoreDue: (run = {}) =>
      service("score_leads_due", { max_count: run.limit ?? 100 }, (value) =>
        Number(value ?? 0),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "lead-scoring",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
