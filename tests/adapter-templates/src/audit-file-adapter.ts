import type {
  AuditBooks,
  AuditFileAdapter,
  AuditFileSource,
  AuditRecord,
} from "better-supabase/audit-files";

import {
  AuditFileError,
  defineAuditFileAdapter,
} from "better-supabase/audit-files";

async function* lines(source: AuditFileSource): AsyncGenerator<string> {
  const decoder = new TextDecoder();
  let buffer = "";

  const chunks:
    | AsyncIterable<string | Uint8Array>
    | Iterable<string | Uint8Array> =
    typeof source === "string" || source instanceof Uint8Array
      ? [source]
      : source;

  for await (const chunk of chunks) {
    buffer +=
      typeof chunk === "string"
        ? chunk
        : decoder.decode(chunk, { stream: true });

    const parts = buffer.split("\n");

    buffer = parts.pop() ?? "";
    yield* parts;
  }

  if (buffer !== "") {
    yield buffer;
  }
}

/**
 * An `AuditFileAdapter` for a made-up JSON Lines format: one account per line.
 * A real adapter reads its format's XML one element at a time and reports what
 * it does not map as `warning` records, so memory stays flat for a large file.
 * Set `version` to the version of the format you follow.
 */
export const exampleAuditFileAdapter: AuditFileAdapter = defineAuditFileAdapter(
  {
    apiVersion: 1,
    key: "example-jsonl-1",
    format: "Example JSON Lines",
    version: "1",
    async *parse(source): AsyncGenerator<AuditRecord> {
      for await (const line of lines(source)) {
        if (line.trim() === "") {
          continue;
        }

        const row: unknown = JSON.parse(line);

        if (
          typeof row !== "object" ||
          row === null ||
          !("code" in row) ||
          !("name" in row) ||
          typeof row.code !== "string" ||
          typeof row.name !== "string"
        ) {
          throw new AuditFileError(
            "AUDIT_FILE_INVALID",
            `bad account line: ${line}`,
          );
        }

        yield {
          kind: "account",
          account: {
            code: row.code,
            name: row.name,
            type: "asset",
            typeAssumed: true,
          },
        };
      }
    },
    *export(books: AuditBooks): Iterable<string> {
      for (const account of books.accounts) {
        yield `${JSON.stringify({ code: account.code, name: account.name })}\n`;
      }
    },
  },
);
