import type { Rule } from "./rules.ts";

import { EMBEDDING_JOB_RULES } from "./embedding-jobs.ts";
import { LIVE_DRIFT_RULES } from "./live-drift.ts";
import { PARTITION_HINT_RULES } from "./partition-hint.ts";

/** The checks that read queues, requests and indexes of the running database. */
export const LIVE_STATE_RULES: readonly Rule[] = [
  ...EMBEDDING_JOB_RULES,
  ...LIVE_DRIFT_RULES,
  ...PARTITION_HINT_RULES,
];
