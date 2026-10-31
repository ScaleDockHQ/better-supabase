// The lims block's fixed values. This file imports nothing, so the client entry
// can read them without the SQL builders.

/** Where a sample is in the laboratory. */
export const LIMS_SAMPLE_STATUSES = [
  "registered",
  "in_testing",
  "completed",
  "released",
  "rejected",
] as const;

/** Whether a result lies inside the method's specification limits. */
export const LIMS_RESULT_OUTCOMES = ["in_spec", "out_of_spec"] as const;
