import { enableFilterTrees } from "../ir/filter-tree.ts";
import { dbExtras } from "./define-extras.ts";
import { provideLeanConnectionRuntime } from "./define-runtime.ts";

/**
 * Installs the connection runtime with every db method and the filter trees in
 * `where`. The server, the adapters and the testing helpers call it; the
 * browser client calls `provideLeanConnectionRuntime()` and leaves `$many`,
 * `$search`, `$stats`, `$decode` and `$decodeReadSet` out of its bundle.
 */
export function provideConnectionRuntime(): void {
  enableFilterTrees();
  provideLeanConnectionRuntime(dbExtras());
}
