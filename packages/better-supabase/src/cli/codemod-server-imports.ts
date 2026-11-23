import type { ExportSpecifier, ImportDeclarationSpecifier } from "oxc-parser";

import { MagicString } from "magic-string";

import type { Codemod, ReviewLine } from "./codemod.ts";

import { parseSource } from "./config-document/parse.ts";

/** The subpath each name moved to out of `better-supabase/server` (ADR 0450). */
const MOVED: Readonly<Record<string, string>> = {
  deleteAccount: "accounts",
  DeleteAccountOptions: "accounts",
  DeleteAccountResult: "accounts",
  endSessions: "accounts",
  lastSignIns: "accounts",
  suspendAccount: "accounts",
  AccountTransport: "accounts",
  EndSessionsResult: "accounts",
  LastSignIn: "accounts",
  SuspendAccountOptions: "accounts",
  SuspendAccountResult: "accounts",
  supportSessions: "accounts",
  supportStorage: "accounts",
  SupportStorageOptions: "accounts",
  claimsFingerprint: "accounts",
  sessionStatusRoute: "accounts",
  SessionStatusBody: "accounts",
  SessionStatusRouteOptions: "accounts",
  SessionStatusServer: "accounts",
  SessionWatchStatus: "accounts",
  csvColumns: "csv",
  toCsv: "csv",
  csvResponse: "csv",
  CsvOptions: "csv",
  CsvResponseOptions: "csv",
  isRateLimitPolicyName: "rate-limit",
  periodSeconds: "rate-limit",
  rateLimitHeader: "rate-limit",
  rateLimitPolicyHeader: "rate-limit",
  RateLimitPolicy: "rate-limit",
  RateLimitState: "rate-limit",
};

/** The name an import or export specifier refers to in the source module. */
function sourceName(
  specifier: ExportSpecifier | ImportDeclarationSpecifier,
): string | undefined {
  const side =
    specifier.type === "ImportSpecifier"
      ? specifier.imported
      : specifier.type === "ExportSpecifier"
        ? specifier.local
        : undefined;

  if (side === undefined) {
    return undefined;
  }

  return side.type === "Literal" ? side.value : side.name;
}

/**
 * Splits each `import` and `export { ... } from "better-supabase/server"` so
 * the names that moved to `server/accounts`, `server/csv` and
 * `server/rate-limit` import from their new subpath. The names that stayed keep
 * their import. A file that does not parse comes back unchanged.
 */
export function moveServerImports(text: string): {
  readonly text: string;
  readonly review: readonly ReviewLine[];
} {
  const parsed = parseSource(text);
  const review: ReviewLine[] = [];

  if (parsed.errors.length > 0) {
    return { text, review };
  }

  const out = new MagicString(text);

  for (const statement of parsed.program.body) {
    if (
      (statement.type !== "ImportDeclaration" &&
        statement.type !== "ExportNamedDeclaration") ||
      statement.source?.value !== "better-supabase/server" ||
      statement.specifiers.length === 0 ||
      statement.specifiers.some(
        (specifier) =>
          specifier.type !== "ImportSpecifier" &&
          specifier.type !== "ExportSpecifier",
      )
    ) {
      continue;
    }

    const groups = new Map<string, string[]>();

    for (const specifier of statement.specifiers) {
      const name = sourceName(specifier);

      const target =
        name !== undefined && Object.hasOwn(MOVED, name)
          ? MOVED[name]
          : undefined;

      const key = target ?? "";

      groups.set(key, [
        ...(groups.get(key) ?? []),
        text.slice(specifier.start, specifier.end),
      ]);
    }

    if (groups.size === 1 && groups.has("")) {
      continue;
    }

    const keyword =
      statement.type === "ImportDeclaration" ? "import" : "export";

    const typeOnly =
      (statement.type === "ImportDeclaration"
        ? statement.importKind
        : statement.exportKind) === "type"
        ? " type"
        : "";

    const quote = text[statement.source.start]!;
    const lineStart = text.lastIndexOf("\n", statement.start - 1) + 1;
    const indent = text.slice(lineStart, statement.start);
    const lines: string[] = [];

    for (const [target, names] of groups) {
      const path =
        target === ""
          ? "better-supabase/server"
          : `better-supabase/server/${target}`;

      lines.push(
        `${keyword}${typeOnly} { ${names.join(", ")} } from ${quote}${path}${quote};`,
      );
    }

    out.overwrite(statement.start, statement.end, lines.join(`\n${indent}`));
    review.push({
      line: text.slice(0, statement.start).split("\n").length,
      message: "import split across better-supabase/server subpaths",
    });
  }

  return { text: out.toString(), review };
}

export function serverImportsCodemod(): Codemod {
  return {
    name: "server-imports",
    description:
      "Import the account, csv and rate-limit helpers from their server subpaths",
    source: moveServerImports,
  };
}
