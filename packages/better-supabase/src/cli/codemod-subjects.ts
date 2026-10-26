/**
 * The 0.29 rename of `records` back to `subjects`, the name it had before 0.15.
 * The config edit is textual, so comments and formatting survive; the SQL edit
 * renames `record` tags in `comment on table` statements.
 */

import type { Codemod, CodemodConfigEdit, ReviewLine } from "./codemod.ts";
import type { Property } from "./sql/config-edit.ts";

import { formatBsbComment, parseBsbComment } from "../sql/index.ts";
import { isRecord } from "./guards.ts";
import {
  closingIndex,
  configObject,
  indentAt,
  mask,
  properties,
  skipSpace,
} from "./sql/config-edit.ts";

interface Edit {
  readonly start: number;
  readonly end: number;
  readonly text: string;
}

const ENVIRONMENT_KEY = /^\$(?:development|production|test|ci)$/;

const lineAt = (source: string, index: number): number =>
  source.slice(0, index).split("\n").length;

function applyEdits(source: string, edits: readonly Edit[]): string {
  let text = source;

  for (const edit of edits.toSorted((a, b) => b.start - a.start)) {
    text = text.slice(0, edit.start) + edit.text + text.slice(edit.end);
  }

  return text;
}

/** The range that removes `prop` with its comma and the space after it. */
function removal(code: string, prop: Property, close: number): Edit {
  const after = skipSpace(code, prop.valueEnd);

  if (code[after] === ",") {
    return { start: prop.start, end: skipSpace(code, after + 1), text: "" };
  }

  return {
    start: prop.start,
    end: after === close ? prop.valueEnd : after,
    text: "",
  };
}

/** Text that adds `entries` before the `}` at `close`. */
function insertion(
  source: string,
  code: string,
  open: number,
  close: number,
  existing: readonly Property[],
  entries: readonly string[],
): Edit {
  const outer = indentAt(source, open);
  const first = existing[0];

  const inner =
    first === undefined ? `${outer}  ` : indentAt(source, first.start);

  let last = close - 1;

  while (last > open && /\s/.test(code[last]!)) {
    last -= 1;
  }

  const body = entries.map((entry) => `\n${inner}${entry},`).join("");

  if (last === open) {
    return { start: open + 1, end: close, text: `${body}\n${outer}` };
  }

  return {
    start: last + 1,
    end: last + 1,
    text: `${code[last] === "," ? "" : ","}${body}`,
  };
}

/** Moves `records` into `subjects` in the object at `open`. */
function renameIn(
  source: string,
  code: string,
  open: number,
  review: ReviewLine[],
): Edit[] {
  const props = properties(source, code, open);
  const close = closingIndex(code, open);

  if (props === undefined || close === -1) {
    return [];
  }

  const edits: Edit[] = [];
  const records = props.find((prop) => prop.key === "records");
  const subjects = props.find((prop) => prop.key === "subjects");

  if (records !== undefined && subjects === undefined) {
    const keyEnd = source.indexOf("records", records.start) + "records".length;
    edits.push({ start: records.start, end: keyEnd, text: "subjects" });
  } else if (records !== undefined && subjects !== undefined) {
    const from =
      code[records.valueStart] === "{"
        ? properties(source, code, records.valueStart)
        : undefined;

    const into =
      code[subjects.valueStart] === "{"
        ? properties(source, code, subjects.valueStart)
        : undefined;

    if (from === undefined || into === undefined) {
      review.push({
        line: lineAt(source, records.start),
        message:
          "`records` and `subjects` are both set and one isn't an object literal: move the `records` entries into `subjects` by hand",
      });
    } else {
      const taken = new Set(into.flatMap((prop) => prop.key ?? []));
      const moved: string[] = [];

      for (const entry of from) {
        if (entry.key !== undefined && taken.has(entry.key)) {
          review.push({
            line: lineAt(source, entry.start),
            message: `\`records.${entry.key}\` is dropped: \`subjects.${entry.key}\` already exists and wins`,
          });
        } else {
          moved.push(source.slice(entry.start, entry.valueEnd));
        }
      }

      if (moved.length > 0) {
        edits.push(
          insertion(
            source,
            code,
            subjects.valueStart,
            closingIndex(code, subjects.valueStart),
            into,
            moved,
          ),
        );
      }

      edits.push(removal(code, records, close));
    }
  }

  for (const prop of props) {
    if (prop.key === undefined || code[prop.valueStart] !== "{") {
      continue;
    }

    if (ENVIRONMENT_KEY.test(prop.key)) {
      edits.push(...renameIn(source, code, prop.valueStart, review));
    } else if (prop.key === "$env") {
      for (const environment of properties(source, code, prop.valueStart) ??
        []) {
        if (code[environment.valueStart] === "{") {
          edits.push(...renameIn(source, code, environment.valueStart, review));
        }
      }
    }
  }

  return edits;
}

function renameJson(value: unknown, review: ReviewLine[]): unknown {
  if (!isRecord(value)) {
    return value;
  }

  const { records, ...rest } = value;
  const out: Record<string, unknown> = { ...rest };

  if (records !== undefined) {
    const subjects = rest["subjects"];

    if (subjects === undefined) {
      out["subjects"] = records;
    } else if (isRecord(records) && isRecord(subjects)) {
      for (const key of Object.keys(records)) {
        if (key in subjects) {
          review.push({
            line: 1,
            message: `\`records.${key}\` is dropped: \`subjects.${key}\` already exists and wins`,
          });
        }
      }

      out["subjects"] = { ...records, ...subjects };
    } else {
      out["records"] = records;
      review.push({
        line: 1,
        message:
          "`records` and `subjects` are both set and one isn't an object: move the `records` entries into `subjects` by hand",
      });
    }
  }

  for (const [key, entry] of Object.entries(out)) {
    if (ENVIRONMENT_KEY.test(key)) {
      out[key] = renameJson(entry, review);
    } else if (key === "$env" && isRecord(entry)) {
      out[key] = Object.fromEntries(
        Object.entries(entry).map(([name, block]) => [
          name,
          renameJson(block, review),
        ]),
      );
    }
  }

  return out;
}

/**
 * `better-supabase.config.*` with `records` renamed to `subjects`, at the top
 * level and in the `$env` and `$<environment>` blocks. Where both keys are set,
 * the `records` entries move into `subjects` and an existing `subjects` entry
 * wins, as the 0.29 config loader merges them.
 */
function recordsToSubjects(source: string, json: boolean): CodemodConfigEdit {
  const review: ReviewLine[] = [];

  if (json) {
    let parsed: unknown;

    try {
      parsed = JSON.parse(source);
    } catch {
      return { ok: false, reason: "the file is not valid JSON" };
    }

    const renamed = renameJson(parsed, review);

    return JSON.stringify(renamed) === JSON.stringify(parsed)
      ? { ok: true, text: source, review }
      : { ok: true, text: `${JSON.stringify(renamed, null, 2)}\n`, review };
  }

  const code = mask(source);
  const open = configObject(code);

  if (open === undefined) {
    return /\brecords\s*:/.test(code)
      ? {
          ok: false,
          reason:
            "no defineConfig({...}) or exported object literal; rename `records` to `subjects` by hand",
        }
      : { ok: true, text: source, review };
  }

  return {
    ok: true,
    text: applyEdits(source, renameIn(source, code, open, review)),
    review,
  };
}

const COMMENT =
  /(comment\s+on\s+table\s+(?:"?[\w$]+"?\.)?"?[\w$]+"?\s+is\s+)'((?:[^']|'')*)'(\s*;)/giu;

/**
 * `sql` with the `@bsb record` tags of its `comment on table` statements
 * renamed to `subject`. A comment that has both keeps `subject` and drops
 * `record`, with a review line.
 */
function recordTagsToSubject(sql: string): {
  readonly text: string;
  readonly review: readonly ReviewLine[];
} {
  const review: ReviewLine[] = [];

  const text = sql.replaceAll(
    COMMENT,
    (statement, head: string, body: string, tail: string, offset: number) => {
      const parsed = parseBsbComment(body.replaceAll("''", "'"));

      if (!parsed.tags.some((tag) => tag.name === "record")) {
        return statement;
      }

      const hasSubject = parsed.tags.some((tag) => tag.name === "subject");

      if (hasSubject) {
        review.push({
          line: lineAt(sql, offset),
          message:
            "The `record` tag is dropped: the comment already has a `subject` tag, which wins",
        });
      }

      const comment = formatBsbComment({
        text: parsed.text,
        tags: parsed.tags.flatMap((tag) =>
          tag.name === "record"
            ? hasSubject
              ? []
              : [{ ...tag, name: "subject" }]
            : [tag],
        ),
      });

      return `${head}'${comment.replaceAll("'", "''")}'${tail}`;
    },
  );

  return { text, review };
}

export const CODEMOD_0_29: Codemod = {
  name: "0.29",
  description:
    "Renames records back to subjects in better-supabase.config.*, reversing the 0.15 rename (at the top level and in the $env and $<environment> blocks; where both are set, the records entries move into subjects and an existing subjects entry wins), and renames @bsb record tags to subject in the comment on table statements of supabase/schemas",
  configFile: recordsToSubjects,
  sqlFile: recordTagsToSubject,
};
