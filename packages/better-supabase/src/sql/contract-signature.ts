import type { BlockSqlContractFunction } from "./context.ts";

/** The contract's argument list with `{id}` resolved, as Postgres prints it. */
export function contractSignature(
  fn: BlockSqlContractFunction,
  idType: string,
): string {
  return fn.args.map((arg) => arg.replaceAll("{id}", idType)).join(", ");
}
