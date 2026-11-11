import type { inferParserType } from "nuqs/server";

import { createLoader, parseAsBoolean, parseAsString } from "nuqs/server";

/** The eval workspace's URL state: the run shown and whether only failures list. */
export const evalSearchParams = {
  run: parseAsString,
  failed: parseAsBoolean.withDefault(false),
};

export const loadEvalParams = createLoader(evalSearchParams);

export type EvalParams = inferParserType<typeof evalSearchParams>;
