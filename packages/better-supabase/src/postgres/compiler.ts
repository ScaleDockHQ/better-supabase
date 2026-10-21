import type { SqlPlan } from "../compile/sql.ts";
import type { Compiler } from "../core/compiler.ts";

import { compileSql } from "../compile/sql.ts";

export const sqlCompiler: Compiler<SqlPlan> = {
  target: "sql",
  compile: compileSql,
};
