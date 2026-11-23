import { dirname, join } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";

import { migrationsDir } from "../sql-layout.ts";

/** The folder of the app's declared rows, next to the migrations. */
export function rowsDir(config: ResolvedConfig): string {
  return join(dirname(migrationsDir(config)), "rows").replaceAll("\\", "/");
}
