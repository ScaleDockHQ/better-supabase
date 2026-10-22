import { posix } from "node:path";

import type { GeneratedFile, ResolvedConfig } from "../../config/index.ts";

import { GENERATED_HEADER } from "./emit.ts";
import { q } from "./shared.ts";

type NavigationConfig = Pick<ResolvedConfig, "output" | "subjects">;

/** One subject with a top-level list route. */
interface ListedSubject {
  readonly type: string;
  readonly label: string;
  readonly href: string;
  readonly record: string;
  readonly permission: string | undefined;
}

function plural(word: string): string {
  if (/[^aeiou]y$/.test(word)) {
    return `${word.slice(0, -1)}ies`;
  }

  if (/(?:s|x|z|ch|sh)$/.test(word)) {
    return `${word}es`;
  }

  return `${word}s`;
}

function label(type: string): string {
  const words = type.split(/[-_]/);
  const last = words.length - 1;

  const named = words
    .map((word, index) => (index === last ? plural(word) : word))
    .join(" ");

  return named.charAt(0).toUpperCase() + named.slice(1);
}

/**
 * The subjects whose `url` has a list route: the path without its last segment,
 * such as `/customers` for `/customers/{id}`. A route with a placeholder before
 * the last segment is nested under another record and has no top-level entry.
 */
export function listedSubjects(
  config: NavigationConfig,
): readonly ListedSubject[] {
  return Object.entries(config.subjects)
    .toSorted(([a], [b]) => a.localeCompare(b))
    .flatMap(([type, entry]) => {
      const url = entry.url;

      if (url === undefined) {
        return [];
      }

      const last = url.lastIndexOf("/");
      const own = url.slice(last) === `/{${entry.id ?? "id"}}`;
      const href = own ? url.slice(0, last) : url;

      if (href === "" || href.includes("{")) {
        return [];
      }

      return [
        {
          type,
          label: label(type),
          href,
          record: url,
          permission: entry.permissions?.["read"],
        },
      ];
    });
}

function navigationFile(
  path: string,
  listed: readonly ListedSubject[],
): GeneratedFile {
  const hrefs = new Set<string>();

  const subjects = listed.filter(
    (subject) => !hrefs.has(subject.href) && hrefs.add(subject.href),
  );

  const items = subjects.map((subject) =>
    [
      "  {",
      `    type: ${q(subject.type)},`,
      `    label: ${q(subject.label)},`,
      `    href: ${q(subject.href)},`,
      `    record: ${q(subject.record)},`,
      `    permission: ${subject.permission === undefined ? "undefined" : q(subject.permission)},`,
      "  },",
    ].join("\n"),
  );

  return {
    path,
    contents: [
      GENERATED_HEADER,
      "",
      "/** A list route for a registered subject, from `subjects.<type>.url`. */",
      "export interface NavigationItem {",
      "  readonly type: string;",
      "  readonly label: string;",
      "  /** The list route. */",
      "  readonly href: string;",
      "  /** The record route, with `{column}` placeholders. */",
      "  readonly record: string;",
      "  /** The permission key `subjects.<type>.permissions.read` names. */",
      "  readonly permission: string | undefined;",
      "}",
      "",
      "export const navigation: readonly NavigationItem[] = [",
      ...items,
      "];",
      "",
    ].join("\n"),
  };
}

function commandsFile(
  path: string,
  subjects: readonly ListedSubject[],
): GeneratedFile {
  const items = subjects.map((subject) =>
    [
      "  {",
      `    id: ${q(`go-to-${subject.type.replaceAll("_", "-")}`)},`,
      `    label: ${q(`Go to ${subject.label.toLowerCase()}`)},`,
      `    group: "Navigation",`,
      `    keywords: [${q(subject.type)}],`,
      `    href: ${q(subject.href)},`,
      `    permission: ${subject.permission === undefined ? "undefined" : q(subject.permission)},`,
      "  },",
    ].join("\n"),
  );

  return {
    path,
    contents: [
      GENERATED_HEADER,
      "",
      "/** A command palette entry that opens a subject's list route. */",
      "export interface Command {",
      "  readonly id: string;",
      "  readonly label: string;",
      "  readonly group: string;",
      "  readonly keywords: readonly string[];",
      "  readonly href: string;",
      "  /** The permission key the command needs, when the subject names one. */",
      "  readonly permission: string | undefined;",
      "}",
      "",
      "export const commands: readonly Command[] = [",
      ...items,
      "];",
      "",
    ].join("\n"),
  };
}

/**
 * `navigation.generated.ts` and `commands.generated.ts` next to the typed
 * client: plain typed arrays with one entry per subject that has a list route,
 * carrying the read permission so the app can hide what the caller can't open.
 * Subjects that share a list route share one navigation entry, the first by
 * type name.
 */
export function emitNavigation(
  config: NavigationConfig,
): readonly GeneratedFile[] {
  const subjects = listedSubjects(config);

  if (subjects.length === 0) {
    return [];
  }

  const dir = posix.dirname(config.output);

  return [
    navigationFile(posix.join(dir, "navigation.generated.ts"), subjects),
    commandsFile(posix.join(dir, "commands.generated.ts"), subjects),
  ];
}
