import { coldRecord } from "../core/cold-start.ts";

// The `next` entry imports this module first, so the mark falls before the
// rest of the entry evaluates. tsdown keeps its side effect (tsdown.config.ts).
coldRecord().timings.evalStart ??= performance.now();
