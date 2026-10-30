import type { BlockSqlContext } from "./context.ts";
import type { AccountingContribution } from "./contributions.ts";

import { sqlString } from "../core/template.ts";

/**
 * Whether the accounting block books this block's documents: accounting is
 * installed and managed, and this is the block's own instance (a block
 * installed under another name books nothing).
 */
export function booksAccounting(ctx: BlockSqlContext): boolean {
  return (
    ctx.instance === ctx.module &&
    ctx.installed("accounting") &&
    ctx.of("accounting").mode !== "custom"
  );
}

/**
 * PL/pgSQL that books a document in the same transaction, or `''` when
 * accounting doesn't book this block's documents.
 */
export function bookSource(
  ctx: BlockSqlContext,
  source: string,
  id: string,
): string {
  return booksAccounting(ctx)
    ? `perform ${ctx.of("accounting").fn("accounting_post_source")}(${sqlString(source)}, ${id}::text);`
    : "";
}

/**
 * PL/pgSQL that undoes a document's entry (deletes a draft, reverses a posted
 * one today), or `''` when accounting doesn't book this block's documents.
 */
export function unbookSource(
  ctx: BlockSqlContext,
  source: string,
  tenant: string,
  id: string,
): string {
  return booksAccounting(ctx)
    ? `perform ${ctx.of("accounting").fn("accounting_reverse_source")}(${tenant}, ${sqlString(source)}, ${id}::text);`
    : "";
}

/** One source's lines function: the document's id in, the entry as JSON out. */
export interface AccountingSource {
  readonly source: string;
  readonly journal: AccountingContribution["journal"];
  /** The function's default name in the block's schema. */
  readonly fn: string;
  /** The function's comment. */
  readonly comment: string;
  /** A SQL `select` that returns the jsonb, reading `source_id`. */
  readonly body: string;
}

/** The lines functions of a block's sources, or `''` when nothing books. */
export function accountingSourcesSql(
  ctx: BlockSqlContext,
  sources: readonly AccountingSource[],
): string {
  if (!booksAccounting(ctx)) {
    return "";
  }

  return sources
    .map(
      (source) => `
${source.comment
  .split("\n")
  .map((line) => `-- ${line}`)
  .join("\n")}
create or replace function ${ctx.fn(source.fn)}(source_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
${source.body}
$$;
revoke execute on function ${ctx.fn(source.fn)}(text) from public, anon, authenticated;
`,
    )
    .join("");
}

/** What `contributes.accounting` returns for a block's sources. */
export function accountingContributions(
  own: BlockSqlContext,
  sources: readonly Pick<AccountingSource, "source" | "journal" | "fn">[],
): readonly AccountingContribution[] {
  return booksAccounting(own)
    ? sources.map((source) => ({
        source: source.source,
        journal: source.journal,
        lines: own.fn(source.fn),
      }))
    : [];
}
