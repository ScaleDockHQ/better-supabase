import type { Rule } from "./rules.ts";

import { AUDIT_EXEMPTION_RULES } from "./audit-exemptions.ts";
import { EMBEDDING_JOB_RULES } from "./embedding-jobs.ts";
import { LIVE_DRIFT_RULES } from "./live-drift.ts";
import { OPEN_ITEMS_DRIFT_RULES } from "./open-items-drift.ts";
import { PARTITION_HINT_RULES } from "./partition-hint.ts";
import { SLOW_STATEMENT_RULES } from "./slow-statements.ts";
import { TASK_STAGE_RULES } from "./task-stages.ts";

/** The checks that read queues, requests and indexes of the running database. */
export const LIVE_STATE_RULES: readonly Rule[] = [
  ...AUDIT_EXEMPTION_RULES,
  ...EMBEDDING_JOB_RULES,
  ...LIVE_DRIFT_RULES,
  ...OPEN_ITEMS_DRIFT_RULES,
  ...PARTITION_HINT_RULES,
  ...SLOW_STATEMENT_RULES,
  ...TASK_STAGE_RULES,
];
