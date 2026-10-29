import type { BlockSqlScope } from "../scope.ts";

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
