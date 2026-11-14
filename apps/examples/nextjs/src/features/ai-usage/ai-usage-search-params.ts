import { createLoader, parseAsStringLiteral } from "nuqs/server";

/** The usage page's range in days: a week, a month, a quarter or every run. */
const USAGE_RANGE_VALUES = ["7", "30", "90", "0"] as const;

export const loadUsageRange = createLoader({
  range: parseAsStringLiteral(USAGE_RANGE_VALUES).withDefault("0"),
});
