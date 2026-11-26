import type { ScanToken, SupportedVersion } from "@supabase/pg-parser";

import {
  PgParser,
  isSupportedVersion,
  unwrapScanResult,
} from "@supabase/pg-parser";

import type { CodeStatement } from "./code-tokens.ts";
import type { FileFacts, SchemaReadError } from "./facts.ts";
import type { RawStatement } from "./read.ts";
import type { SqlPart, SqlStatement } from "./statements.ts";

import { codeStatementsFrom } from "./code-tokens.ts";
import { factsFrom } from "./read.ts";
import { Source } from "./source.ts";
import {
  blankedFrom,
  partsFrom,
  rawStatementsFrom,
  statementsFrom,
} from "./statements.ts";

export type * from "./facts.ts";

export type { SqlPart, SqlStatement } from "./statements.ts";

export type { CodeStatement, CodeToken } from "./code-tokens.ts";

export { indexOfWords, nameAt, wordsAt } from "./code-tokens.ts";

/** The Postgres grammar used when `db.major_version` is missing or unknown. */
const DEFAULT_VERSION: SupportedVersion = 17;

const parsers = new Map<SupportedVersion, PgParser<SupportedVersion>>();

/** The grammar the reader uses for `db.major_version`. */
function grammarFor(major: number | undefined): SupportedVersion {
  return major !== undefined && isSupportedVersion(major)
    ? major
    : DEFAULT_VERSION;
}

function parserFor(major: number | undefined): PgParser<SupportedVersion> {
  const version = grammarFor(major);

  const known = parsers.get(version);

  if (known !== undefined) {
    return known;
  }

  const created = new PgParser({ version });

  parsers.set(version, created);

  return created;
}

/** Thrown when a file does not parse, so `gen` and doctor can name it. */
export class SchemaReadFailure extends Error {
  override readonly name = "SchemaReadFailure";
  readonly details: SchemaReadError;

  constructor(details: SchemaReadError) {
    super(
      `${details.path}:${details.line}:${details.column}: ${details.message} (Postgres ${details.major} grammar)`,
    );
    this.details = details;
  }
}

/** Facts read ahead of time, by file text, for code that cannot wait. */
const primed = new Map<string, FileFacts>();

/**
 * Empty facts for texts a lenient read rejected. Kept apart from `primed` so a
 * later read parses the text again and reports it with its own grammar.
 */
const unparsed = new Map<string, FileFacts>();

/**
 * The facts of one SQL text. A text that does not parse throws a
 * `SchemaReadFailure` that names `path`.
 *
 * @param text - The SQL file contents.
 * @param options - The file path for errors and the Postgres major version.
 * @returns What the file declares.
 */
export async function getFileFacts(
  text: string,
  options: { path?: string; majorVersion?: number } = {},
): Promise<FileFacts> {
  const known = primed.get(text);

  if (known !== undefined) {
    return known;
  }

  const parser = parserFor(options.majorVersion);
  const parsed = await parser.parse(text);

  if (parsed.error !== undefined) {
    const source = new Source(text, []);

    throw new SchemaReadFailure({
      path: options.path ?? "<sql>",
      message: parsed.error.message,
      line: source.lineAt(parsed.error.position),
      column: source.columnAt(parsed.error.position),
      major: grammarFor(options.majorVersion),
    });
  }

  const scanned = await scanSql(text, options);

  // SAFETY: `stmts` is the parser's list of `{ stmt, stmt_location, stmt_len }`,
  // which is the shape of `RawStatement`.
  const statements: readonly RawStatement[] = parsed.tree.stmts ?? [];
  const facts = factsFrom(new Source(text, scanned), statements);

  primed.set(text, facts);

  return facts;
}

/**
 * Reads every file once and keeps the result for `factsOf`.
 *
 * @param files - The files to read.
 * @param options - The Postgres major version.
 * @returns The facts of each file, in the order of `files`.
 */
export async function getSchemaFacts(
  files: readonly { readonly path: string; readonly text: string }[],
  options: { majorVersion?: number } = {},
): Promise<readonly FileFacts[]> {
  const read: FileFacts[] = [];

  // One file at a time, so only one parse tree is alive at once.
  for (const file of files) {
    read.push(await getFileFacts(file.text, { ...options, path: file.path }));
  }

  return read;
}

/**
 * Like `readSchemaFacts`, but a file that does not parse keeps empty facts
 * instead of throwing, so a check that must still run (doctor) can go on.
 *
 * @param files - The files to read.
 * @param options - The Postgres major version.
 * @returns The failures, one per file that did not parse.
 */
export async function getSchemaFactsLeniently(
  files: readonly { readonly path: string; readonly text: string }[],
  options: { majorVersion?: number } = {},
): Promise<readonly SchemaReadError[]> {
  const failures: SchemaReadError[] = [];

  for (const file of files) {
    try {
      await getFileFacts(file.text, { ...options, path: file.path });
    } catch (error) {
      if (!(error instanceof SchemaReadFailure)) {
        throw error;
      }

      failures.push(error.details);
      unparsed.set(file.text, factsFrom(new Source(file.text, []), []));
    }
  }

  return failures;
}

/**
 * The facts of a text that `readSchemaFacts` read before.
 *
 * @param text - A file's contents.
 * @returns What the file declares.
 */
export function factsOf(text: string): FileFacts {
  const known = primed.get(text) ?? unparsed.get(text);

  if (known === undefined) {
    throw new Error(
      "The SQL reader has not read this text yet; await readSchemaFacts first.",
    );
  }

  return known;
}

const scans = new Map<
  SupportedVersion,
  Map<string, Promise<readonly ScanToken[]>>
>();

/**
 * The scanned characters `scans` keeps, oldest dropped first. A text is scanned
 * again by the readers that prime it, but a large project's every migration and
 * function body must not stay in memory.
 */
const SCANNED_CHARS_MAX = 2_000_000;
let scannedChars = 0;

/**
 * The tokens of a SQL text, comments included, with byte offsets. A codemod
 * rewrites names through them, so a string or a comment never matches.
 *
 * @param text - The SQL file contents.
 * @param options - The Postgres major version.
 * @returns The scanner's tokens.
 */
export async function scanSql(
  text: string,
  options: { majorVersion?: number } = {},
): Promise<readonly ScanToken[]> {
  const version = grammarFor(options.majorVersion);
  let byText = scans.get(version);

  if (byText === undefined) {
    byText = new Map();
    scans.set(version, byText);
  }

  let tokens = byText.get(text);

  if (tokens !== undefined) {
    return tokens;
  }

  tokens = unwrapScanResult(parserFor(version).scan(text));
  byText.set(text, tokens);
  scannedChars += text.length;

  for (const [grammar, kept] of scans) {
    for (const [oldest] of kept) {
      if (scannedChars <= SCANNED_CHARS_MAX || oldest === text) {
        break;
      }

      kept.delete(oldest);
      scannedChars -= oldest.length;
    }

    if (kept.size === 0) {
      scans.delete(grammar);
    }
  }

  return tokens;
}

/** One statement of a parsed file, with its byte range in the text. */
export interface ParsedStatement {
  /** `{ InsertStmt: {...} }`: one key that names the node type. */
  readonly stmt: unknown;
  readonly start: number;
  /** Zero means the statement runs to the end of the text. */
  readonly length: number;
}

/**
 * The parse tree of each statement, for a reader that checks a file's shape
 * instead of collecting facts (the declared rows). A text that does not parse
 * throws a `SchemaReadFailure` that names `path`.
 *
 * @param text - The SQL file contents.
 * @param options - The file path for errors and the Postgres major version.
 * @returns The statements in source order.
 */
export async function parseStatements(
  text: string,
  options: { path?: string; majorVersion?: number } = {},
): Promise<readonly ParsedStatement[]> {
  const parsed = await parserFor(options.majorVersion).parse(text);

  if (parsed.error !== undefined) {
    const source = new Source(text, []);

    throw new SchemaReadFailure({
      path: options.path ?? "<sql>",
      message: parsed.error.message,
      line: source.lineAt(parsed.error.position),
      column: source.columnAt(parsed.error.position),
      major: grammarFor(options.majorVersion),
    });
  }

  // SAFETY: `stmts` is the parser's list of `{ stmt, stmt_location, stmt_len }`.
  const statements = (parsed.tree.stmts ?? []) as readonly {
    readonly stmt: unknown;
    readonly stmt_location?: number;
    readonly stmt_len?: number;
  }[];

  return statements.map((statement) => ({
    stmt: statement.stmt,
    start: statement.stmt_location ?? 0,
    length: statement.stmt_len ?? 0,
  }));
}

/** Statements split ahead of time, by file text. */
const split = new Map<string, readonly SqlStatement[]>();
const blanked = new Map<string, string>();

/** The length of each raw statement, so the text itself is not kept twice. */
const raw = new Map<string, readonly number[]>();
const parted = new Map<string, readonly SqlPart[]>();

/**
 * Splits every text into statements with the scanner, so `statementsOf` can
 * answer synchronously. The scanner needs no valid grammar, so a text that does
 * not parse still splits.
 *
 * @param texts - The SQL texts to split.
 * @param options - The Postgres major version.
 */
export async function primeStatements(
  texts: readonly string[],
  options: { majorVersion?: number } = {},
): Promise<void> {
  for (const text of texts) {
    if (split.has(text)) {
      continue;
    }

    const scanned = await scanSql(text, options);

    const source = new Source(text, scanned);

    split.set(text, statementsFrom(source));
    blanked.set(text, blankedFrom(source));
    raw.set(
      text,
      rawStatementsFrom(source).map((statement) => statement.length),
    );
    parted.set(text, partsFrom(source));
  }
}

/**
 * The statements of a text that `primeStatements` split before.
 *
 * @param text - A SQL text.
 * @returns Its statements, comments dropped, with the line each starts on.
 */
export function statementsOf(text: string): readonly SqlStatement[] {
  const known = split.get(text);

  if (known === undefined) {
    throw new Error(
      "The SQL reader has not split this text yet; await primeStatements first.",
    );
  }

  return known;
}

/**
 * A text cut into code, string literals, dollar-quoted bodies and comments.
 *
 * @param text - A SQL text that `primeStatements` scanned before.
 * @returns The parts in source order; they join back to the text.
 */
export function partsOf(text: string): readonly SqlPart[] {
  const known = parted.get(text);

  if (known === undefined) {
    throw new Error(
      "The SQL reader has not scanned this text yet; await primeStatements first.",
    );
  }

  return known;
}

const coded = new Map<string, readonly CodeStatement[]>();

/**
 * Reads every text into code tokens, bodies included, so `codeStatementsOf` can
 * answer synchronously. A text the scanner rejects keeps no statements.
 *
 * @param texts - The SQL texts to read.
 * @param options - The Postgres major version.
 */
export async function primeCodeStatements(
  texts: readonly string[],
  options: { majorVersion?: number } = {},
): Promise<void> {
  for (const text of texts) {
    if (!coded.has(text)) {
      coded.set(text, await getCodeStatements(text, options));
    }
  }
}

/**
 * The code statements of a text, like `codeStatementsOf`, read now and not kept
 * unless `primeCodeStatements` read it before, for a reader that goes through
 * many texts once.
 *
 * @param text - A SQL text.
 * @param options - The Postgres major version.
 * @returns Its statements, or none when the scanner rejects the text.
 */
export async function getCodeStatements(
  text: string,
  options: { majorVersion?: number } = {},
): Promise<readonly CodeStatement[]> {
  const known = coded.get(text);

  if (known !== undefined) {
    return known;
  }

  try {
    return await codeStatementsFrom(text, (body) => scanSql(body, options));
  } catch {
    return [];
  }
}

/**
 * The statements of a text that `primeCodeStatements` read before, as code
 * tokens: no comments, string literals as one token and dollar-quoted bodies
 * read in place one depth deeper.
 *
 * @param text - A SQL text.
 * @returns Its statements.
 */
export function codeStatementsOf(text: string): readonly CodeStatement[] {
  const known = coded.get(text);

  if (known === undefined) {
    throw new Error(
      "The SQL reader has not tokenized this text yet; await primeCodeStatements first.",
    );
  }

  return known;
}

/**
 * The statements of a text as written, each with its comments and closing
 * semicolon, for a writer that moves statements between files.
 *
 * @param text - A SQL text that `primeStatements` scanned before.
 * @returns The statements in source order.
 */
export function rawStatementsOf(text: string): readonly string[] {
  const lengths = raw.get(text);

  if (lengths === undefined) {
    throw new Error(
      "The SQL reader has not scanned this text yet; await primeStatements first.",
    );
  }

  let start = 0;

  return lengths.map((length) => {
    start += length;

    return text.slice(start - length, start);
  });
}

/**
 * A text without its comments, for a reader that matches on the code only.
 * Strings, quoted names and dollar quotes keep their comment-like text.
 *
 * @param text - A SQL text that `primeStatements` scanned before.
 * @returns The text without comments, line comments gone and block comments one
 *   space that keeps their newlines, so line numbers hold.
 */
export function withoutComments(text: string): string {
  const known = blanked.get(text);

  if (known === undefined) {
    throw new Error(
      "The SQL reader has not scanned this text yet; await primeStatements first.",
    );
  }

  return known;
}

/** A statement as whitespace-collapsed text without its closing semicolon. */
const collapsed = (statement: string): string =>
  statement.replaceAll(/\s+/g, " ").trim().replace(/\s*;$/, "");

/**
 * The canonical text of a SQL text: the parser's deparse of its tree, so
 * whitespace, comments, keyword case and identifier quoting that mean the same
 * thing compare equal.
 *
 * @param text - The SQL text.
 * @param options - The Postgres major version.
 * @returns The deparsed text (empty for a text with no statement), or
 *   `undefined` when the text does not parse.
 */
export async function canonicalSql(
  text: string,
  options: { majorVersion?: number } = {},
): Promise<string | undefined> {
  const parser = parserFor(options.majorVersion);
  const parsed = await parser.parse(text);

  if (parsed.error !== undefined) {
    return undefined;
  }

  if ((parsed.tree.stmts ?? []).length === 0) {
    return "";
  }

  const deparsed = await parser.deparse(parsed.tree);

  return deparsed.error === undefined ? deparsed.sql : undefined;
}

/**
 * The key two statements are compared by: their canonical text, or their
 * whitespace-collapsed text when one does not parse.
 *
 * @param statement - One statement.
 * @param options - The Postgres major version.
 * @returns The comparison key.
 */
export async function canonicalKey(
  statement: string,
  options: { majorVersion?: number } = {},
): Promise<string> {
  return (await canonicalSql(statement, options)) ?? collapsed(statement);
}
