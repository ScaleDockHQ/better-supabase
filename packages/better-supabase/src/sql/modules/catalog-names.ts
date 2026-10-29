import type { BlockSqlContext } from "../context.ts";
import type { RankSql } from "../rank-sql.ts";
import type { BlockSqlScope } from "../scope.ts";

import { rankSql } from "../rank-sql.ts";

export interface Names {
  /** The block's scope checks. */
  readonly scope: BlockSqlScope;
  readonly fn: (name: string) => string;
  readonly manage: string;
  readonly read: string;
  readonly create: string;
  readonly update: string;
  readonly remove: string;
  readonly categoryCreate: string;
  readonly categoryUpdate: string;
  readonly categoryDelete: string;
}

/** `blocks.catalog.options.rankType`: rank keys or integer positions. */
export function catalogRank(ctx: BlockSqlContext): RankSql {
  const type = ctx.text("rankType", "text");

  if (type !== "text" && type !== "integer") {
    throw new TypeError(
      'blocks.catalog.options.rankType must be "text" or "integer"',
    );
  }

  return rankSql(type);
}
