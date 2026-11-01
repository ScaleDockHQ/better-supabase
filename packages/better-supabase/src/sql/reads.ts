import type { ReadType } from "../core/read-type.ts";
import type { BlockSqlLink } from "./links.ts";

/** The type of a read's argument; `id` is the module's id type. */
export type BlockSqlReadArgType = "bool" | "date" | "id" | "int" | "text";

/** One argument of a block read. */
export interface BlockSqlReadArg {
  /** The SQL function's parameter name. */
  readonly param: string;
  readonly type: BlockSqlReadArgType;
  readonly optional?: true;
}

/**
 * One composed read a module ships (ADR 0177): a `stable`, `security invoker`
 * function that returns `jsonb`, so a page loads a board, a queue or an
 * overview in one call. `gen` writes `reads` and a result type for each, and
 * the block's client exposes it as a method.
 */
export interface BlockSqlRead {
  /** The method on the block's client and the key in `s.blocks`. */
  readonly name: string;
  /** The function, as the module passes it to `ctx.fn`. */
  readonly function: string;
  /** The arguments by the key the client method takes. */
  readonly args: Readonly<Record<string, BlockSqlReadArg>>;
  /** The JSON the function returns. */
  readonly result: ReadType;
  readonly summary: string;
}

/** Declares a read in one place. */
export const declareRead = (
  name: string,
  fn: string,
  args: BlockSqlRead["args"],
  result: ReadType,
  summary: string,
): BlockSqlRead => ({ name, function: fn, args, result, summary });

/** The SQL type of an argument, for the contract. */
export function readArgSqlType(type: BlockSqlReadArgType): string {
  return {
    bool: "boolean",
    date: "date",
    id: "{id}",
    int: "integer",
    text: "text",
  }[type];
}

/** The TypeScript type of an argument. */
export function readArgSource(type: BlockSqlReadArgType): string {
  return {
    bool: "boolean",
    date: "string",
    id: "string",
    int: "number",
    text: "string",
  }[type];
}

/** What a module declares about how it composes with others (ADR 0177). */
export interface BlockSqlComposition {
  /** The links this module declares to other blocks' entities. */
  readonly links?: readonly BlockSqlLink[];
  /** The composed reads this module ships, one call per page. */
  readonly reads?: readonly BlockSqlRead[];
}
