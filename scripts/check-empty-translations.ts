// Fails when a page of the Next.js example has an empty translation. The pages
// declared in `gen.entityPages` list their message keys in the generated
// `entityRoutes` manifest (ADR 0879). The example extracts its messages into
// `messages/<locale>.po`, so a page's strings sit under the namespace of its
// name (`risks.<hash>`) and a literal key sits under its own `msgctxt`. Every
// entry of either kind must have a non-empty `msgstr` in every locale, because
// extraction adds a new message with an empty one and nothing else fails while
// it stays empty (EX-052, EX-706, EX-1268).
// Run with `node scripts/check-empty-translations.ts`.
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { argv, exit } from "node:process";

import type { EntityRouteText } from "./entity-routes.ts";

import { readEntityRoutes } from "./entity-routes.ts";

const MESSAGES = "apps/examples/nextjs/messages";

export interface PoEntry {
  readonly context: string;
  readonly id: string;
  readonly text: string;
}

const quoted = (line: string): string =>
  /^\s*"(.*)"\s*$/.exec(line)?.[1]?.replaceAll(String.raw`\"`, '"') ?? "";

/**
 * The messages of a `.po` file, without the header and without obsolete
 * entries.
 */
export function parsePo(source: string): readonly PoEntry[] {
  const entries: PoEntry[] = [];

  for (const block of source.split(/\n{2,}/)) {
    let context = "";
    let id = "";
    let text = "";
    let field: "context" | "id" | "text" | undefined;

    for (const line of block.split("\n")) {
      if (line.startsWith("msgctxt ")) {
        field = "context";
        context = quoted(line.slice(8));
      } else if (line.startsWith("msgid ")) {
        field = "id";
        id = quoted(line.slice(6));
      } else if (line.startsWith("msgstr ")) {
        field = "text";
        text = quoted(line.slice(7));
      } else if (line.startsWith('"') && field !== undefined) {
        const part = quoted(line);

        if (field === "context") {
          context += part;
        } else if (field === "id") {
          id += part;
        } else {
          text += part;
        }
      }
    }

    if (id !== "") {
      entries.push({ context, id, text });
    }
  }

  return entries;
}

/** Whether a message belongs to a page: its own key, or its name as namespace. */
export const belongsTo = (entry: PoEntry, page: EntityRouteText): boolean =>
  page.messageKeys.includes(entry.context) ||
  entry.context.startsWith(`${page.name}.`);

export interface TranslationReport {
  readonly problems: readonly string[];
  readonly checked: number;
  readonly pages: number;
}

/** The empty translations of every page of `routes`, per locale file. */
export function checkTranslations(
  routes: readonly EntityRouteText[],
  files: Readonly<Record<string, string>>,
): TranslationReport {
  const problems: string[] = [];
  let checked = 0;

  for (const [file, source] of Object.entries(files)) {
    const entries = parsePo(source);

    for (const page of routes) {
      for (const entry of entries.filter((each) => belongsTo(each, page))) {
        checked += 1;

        if (entry.text.trim() === "") {
          problems.push(
            `${file}: "${entry.context}" (${page.entity}, ${page.route}) has an empty msgstr for "${entry.id.slice(0, 60)}"`,
          );
        }
      }
    }
  }

  return { problems, checked, pages: routes.length };
}

/** Reads every `.po` file of the example's messages folder. */
export function readMessageFiles(
  dir = MESSAGES,
): Readonly<Record<string, string>> {
  return Object.fromEntries(
    readdirSync(dir)
      .filter((name) => name.endsWith(".po"))
      .map((name) => [name, readFileSync(join(dir, name), "utf-8")]),
  );
}

if (argv[1] === import.meta.filename) {
  const routes = readEntityRoutes();

  if (routes.length === 0) {
    console.error(
      "No entity pages found in the generated route manifest; run `pnpm db:gen`.",
    );

    exit(1);
  }

  const report = checkTranslations(routes, readMessageFiles());

  console.log(
    `Translations: ${report.checked} messages of ${report.pages} entity pages, ${report.problems.length} empty.`,
  );

  if (report.problems.length > 0) {
    for (const problem of report.problems) {
      console.error(problem);
    }

    exit(1);
  }
}
