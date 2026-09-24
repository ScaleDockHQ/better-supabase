import type { Compiler } from '../core/compiler.ts';

import { compileSql, type SqlPlan } from '../compile/sql.ts';

export const sqlCompiler: Compiler<SqlPlan> = {
  target: 'sql',
  compile: compileSql,
};
