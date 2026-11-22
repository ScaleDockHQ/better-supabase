import type { ScanToken, SupportedVersion } from "@supabase/pg-parser";

import {
  PgParser,
  isSupportedVersion,
  unwrapScanResult,
} from "@supabase/pg-parser";

import type { FileFacts, SchemaReadError } from "./facts.ts";
import type { RawStatement } from "./read.ts";

import { factsFrom } from "./read.ts";
import { Source } from "./source.ts";

export type * from "./facts.ts";

/** The Postgres grammar used when `db.major_version` is missing or unknown. */
const DEFAULT_VERSION: SupportedVersion = 17;

const parsers = new Map<SupportedVersion, PgParser<SupportedVersion>>();

function parserFor(major: number | undefined): PgParser<SupportedVersion> {
  const version =
    major !== undefined && isSupportedVersion(major) ? major : DEFAULT_VERSION;

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
      `${details.path}:${details.line}:${details.column}: ${details.message}`,
    );
    this.details = details;
  }
}

/** Facts read ahead of time, by file text, for code that cannot wait. */
const primed = new Map<string, FileFacts>();

/**
 * The facts of one SQL text. A text that does not parse throws a
 * `SchemaReadFailure` that names `path`.
 *
 * @param text - The SQL file contents.
 * @param options - The file path for errors and the Postgres major version.
 * @returns What the file declares.
 */
export async function readFileFacts(
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
    });
  }

  const scanned = await unwrapScanResult(parser.scan(text));

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
export async function readSchemaFacts(
  files: readonly { readonly path: string; readonly text: string }[],
  options: { majorVersion?: number } = {},
): Promise<readonly FileFacts[]> {
  return Promise.all(
    files.map((file) =>
      readFileFacts(file.text, { ...options, path: file.path }),
    ),
  );
}

/**
 * Like `readSchemaFacts`, but a file that does not parse keeps empty facts
 * instead of throwing, so a check that must still run (doctor) can go on.
 *
 * @param files - The files to read.
 * @param options - The Postgres major version.
 * @returns The failures, one per file that did not parse.
 */
export async function readSchemaFactsLeniently(
  files: readonly { readonly path: string; readonly text: string }[],
  options: { majorVersion?: number } = {},
): Promise<readonly SchemaReadError[]> {
  const failures: SchemaReadError[] = [];

  await Promise.all(
    files.map(async (file) => {
      try {
        await readFileFacts(file.text, { ...options, path: file.path });
      } catch (error) {
        if (!(error instanceof SchemaReadFailure)) {
          throw error;
        }

        failures.push(error.details);
        primed.set(file.text, factsFrom(new Source(file.text, []), []));
      }
    }),
  );

  return failures;
}

/**
 * The facts of a text that `readSchemaFacts` read before.
 *
 * @param text - A file's contents.
 * @returns What the file declares.
 */
export function factsOf(text: string): FileFacts {
  const known = primed.get(text);

  if (known === undefined) {
    throw new Error(
      "The SQL reader has not read this text yet; await readSchemaFacts first.",
    );
  }

  return known;
}

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
  return unwrapScanResult(parserFor(options.majorVersion).scan(text));
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
