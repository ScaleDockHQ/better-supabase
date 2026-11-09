import type { Codemod, ReviewLine } from "./codemod.ts";

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

const IMPORT =
  /^([ \t]*)(import|export)(\s+type)?\s*\{([^}]*)\}\s*from\s*(["'])better-supabase\/server\5;?/gm;

function entryName(entry: string): string {
  return entry
    .replace(/^type\s+/, "")
    .split(/\s+as\s+/)[0]!
    .trim();
}

/**
 * Splits each `import` and `export { ... } from "better-supabase/server"` so
 * the names that moved to `server/accounts`, `server/csv` and
 * `server/rate-limit` import from their new subpath. The names that stayed keep
 * their import.
 */
export function moveServerImports(text: string): {
  readonly text: string;
  readonly review: readonly ReviewLine[];
} {
  const review: ReviewLine[] = [];

  const next = text.replaceAll(
    IMPORT,
    (
      whole: string,
      indent: string,
      keyword: string,
      typeOnly: string | undefined,
      list: string,
      quote: string,
      offset: number,
    ) => {
      const entries = list
        .split(",")
        .map((entry) => entry.trim())
        .filter((entry) => entry !== "");

      const groups = new Map<string, string[]>();

      for (const entry of entries) {
        const target = Object.hasOwn(MOVED, entryName(entry))
          ? MOVED[entryName(entry)]
          : undefined;

        const key = target ?? "";
        groups.set(key, [...(groups.get(key) ?? []), entry]);
      }

      if (groups.size === 1 && groups.has("")) {
        return whole;
      }

      const head = `${indent}${keyword}${typeOnly ?? ""}`;
      const lines: string[] = [];

      for (const [target, names] of groups) {
        const path =
          target === ""
            ? "better-supabase/server"
            : `better-supabase/server/${target}`;

        lines.push(
          `${head} { ${names.join(", ")} } from ${quote}${path}${quote};`,
        );
      }

      review.push({
        line: text.slice(0, offset).split("\n").length,
        message: "import split across better-supabase/server subpaths",
      });

      return lines.join("\n");
    },
  );

  return { text: next, review };
}

export function serverImportsCodemod(): Codemod {
  return {
    name: "server-imports",
    description:
      "Import the account, csv and rate-limit helpers from their server subpaths",
    source: moveServerImports,
  };
}
