import { coldRecord } from "../core/cold-start.ts";

// The `next` entry imports this module first, so the mark falls before the
// rest of the entry evaluates. tsdown keeps its side effect (tsdown.config.ts).
// oxlint-disable-next-line react-doctor/no-impure-call-at-module-scope -- the mark records when the module evaluates, once per process.
coldRecord().timings.evalStart ??= performance.now();
