import { walk } from "oxc-walker";

import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import { lineColumn, parseSource } from "../config-document/parse.ts";

/** A call of one of Next's cache functions, found through its import. */
export interface NextCacheCall {
  readonly name: "refresh" | "revalidateTag" | "updateTag";
  /** The call's offset in the text. */
  readonly start: number;
  /** The call's first argument, as written, or `undefined`. */
  readonly argument: string | undefined;
}

const NAMES = new Set(["refresh", "revalidateTag", "updateTag"]);

/**
 * The calls `text` makes to `updateTag`, `revalidateTag` and `refresh` from
 * `next/cache`.
 */
export function nextCacheCalls(text: string): NextCacheCall[] {
  if (!text.includes("next/cache")) {
    return [];
  }

  const { program } = parseSource(text);
  const locals = new Map<string, NextCacheCall["name"]>();

  for (const statement of program.body) {
    if (
      statement.type !== "ImportDeclaration" ||
      statement.source.value !== "next/cache"
    ) {
      continue;
    }

    for (const specifier of statement.specifiers) {
      if (
        specifier.type === "ImportSpecifier" &&
        specifier.imported.type === "Identifier" &&
        NAMES.has(specifier.imported.name)
      ) {
        // SAFETY: `NAMES` holds exactly the union's members.
        locals.set(
          specifier.local.name,
          specifier.imported.name as NextCacheCall["name"],
        );
      }
    }
  }

  const calls: NextCacheCall[] = [];

  walk(program, {
    enter(node) {
      if (node.type !== "CallExpression" || node.callee.type !== "Identifier") {
        return;
      }

      const name = locals.get(node.callee.name);
      const [first] = node.arguments;

      if (name) {
        calls.push({
          name,
          start: node.start,
          argument: first ? text.slice(first.start, first.end) : undefined,
        });
      }
    },
  });

  return calls;
}

/** Whether any source keeps a read with `bsb.kept(`. */
const keepsReads = (context: DoctorContext): boolean =>
  context.sources.some((file) => /\bkept\s*\(/.test(file.text));

/**
 * `updateTag` or `revalidateTag` in an app that keeps reads (BS648): they
 * expire Next's cache and leave the kept entry, which a Runtime Cache or
 * Postgres store keeps for every instance. `bsb.expireTags` does both.
 */
function tagCallsBesideKept(context: DoctorContext): FindingInput[] {
  if (!keepsReads(context)) {
    return [];
  }

  return context.sources.flatMap((file) =>
    nextCacheCalls(file.text)
      .filter((call) => call.name !== "refresh")
      .map((call) => {
        const line = lineColumn(file.text, call.start).line;

        return {
          message: `${file.path} calls ${call.name}() and the app keeps reads with bsb.kept(). That expires Next's cache but not the kept store, so the next read on any instance serves the old entry until its life ends. Call \`await bsb.expireTags([...])\` instead, which expires both and resolves once the store has them. \`better-supabase codemod expire-tags\` lists the calls to change.`,
          target: `${file.path}:${String(line)}`,
          location: { file: file.path, line },
        };
      }),
  );
}

/**
 * `refresh()` with no tag expiry in the same file, in an app that keeps reads
 * (BS649): the re-render reads the kept entries again, so a write that expired
 * nothing shows the old data.
 */
function refreshWithoutTags(context: DoctorContext): FindingInput[] {
  if (!keepsReads(context)) {
    return [];
  }

  return context.sources.flatMap((file) => {
    const calls = nextCacheCalls(file.text);

    if (
      !calls.some((call) => call.name === "refresh") ||
      calls.some((call) => call.name !== "refresh") ||
      file.text.includes("expireTags")
    ) {
      return [];
    }

    const first = calls.find((call) => call.name === "refresh");
    const line = lineColumn(file.text, first?.start ?? 0).line;

    return [
      {
        message: `${file.path} calls refresh() and expires no tags, while the app keeps reads with bsb.kept(). The re-render reads the kept entries again, so the page shows the data from before the write. Expire what the write changed with \`await bsb.expireTags(tableTags("table"))\` (or name \`invalidates\` on bsb.action), then refresh.`,
        target: `${file.path}:${String(line)}`,
        location: { file: file.path, line },
      },
    ];
  });
}

export const KEPT_EXPIRY_RULES: readonly Rule[] = [
  {
    code: "BS648",
    severity: "warning",
    title: "updateTag or revalidateTag beside bsb.kept",
    description:
      "`updateTag` and `revalidateTag` expire Next's cache and leave the entries of `bsb.kept()`, which a shared store keeps for every instance. Call `bsb.expireTags()`, which expires both.",
    check: tagCallsBesideKept,
  },
  {
    code: "BS649",
    severity: "warning",
    title: "refresh() without expiring tags beside bsb.kept",
    description:
      "A file calls `refresh()` from `next/cache` and expires no tags while the app keeps reads with `bsb.kept()`. The re-render reads the kept entries again and shows the data from before the write. Expire the changed tags with `bsb.expireTags()`, then refresh.",
    check: refreshWithoutTags,
  },
];
