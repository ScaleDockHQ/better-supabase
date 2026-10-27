/**
 * The 0.15 data contract rewrite: repository reads fold into `list`, `page`,
 * `get` and `count`, and the `*Many` writes into `create`, `update`, `upsert`
 * and `delete`. Calls whose arguments aren't an object literal keep their old
 * name and are listed for review.
 */

import type { OptionRename, ReviewLine } from "./codemod.ts";

import { closingIndex, mask, properties } from "./sql/config-edit.ts";

/** The query guards named after the retired verbs. */
export const DATA_CONTRACT_OPTIONS: readonly OptionRename[] = [
  { call: "guards", from: "noUnboundedFindMany", to: "noUnboundedList" },
  {
    call: "guards",
    from: "noDeleteManyWithoutWhere",
    to: "noDeleteWithoutWhere",
  },
];

/** The lint rules named after the retired verbs. */
export const DATA_CONTRACT_STRINGS: Readonly<Record<string, string>> = {
  "better-supabase/no-unbounded-find-many": "better-supabase/no-unbounded-list",
  "better-supabase/no-delete-many-without-where":
    "better-supabase/no-empty-where",
};

const RENAMED: Readonly<Record<string, string>> = {
  findMany: "list",
  paginate: "page",
  findById: "get",
  createMany: "create",
  upsertMany: "upsert",
};

const CALL =
  /\.(findMany|paginate|findById|createMany|upsertMany|updateMany|deleteMany|findUnique|findOnly|findFirst|exists)(\s*)\(/g;

interface Edit {
  readonly start: number;
  readonly end: number;
  readonly text: string;
}

interface Call {
  readonly method: string;
  /** Index of the method name, after the `.`. */
  readonly name: number;
  readonly open: number;
  readonly close: number;
}

const REVIEW =
  "Rewrite this call by hand: its arguments aren't an object literal (see the 0.14 to 0.15 guide's data contract table)";

export interface DataContractOptions {
  /**
   * Rewrite calls in comments and strings too, for Markdown and MDX pages whose
   * code blocks are plain text.
   */
  readonly raw?: boolean;
}

/**
 * Rewrites the 0.14 repository methods to the 0.15 data contract. A call nested
 * in another rewritten call's arguments is rewritten on the next pass.
 */
export function rewriteDataContract(
  source: string,
  options: DataContractOptions = {},
): { text: string; review: ReviewLine[] } {
  let text = source;

  for (let pass = 0; pass < 4; pass += 1) {
    const next = rewritePass(text, options);

    if (next.text === text) {
      return next;
    }

    text = next.text;
  }

  return rewritePass(text, options);
}

function rewritePass(
  source: string,
  options: DataContractOptions,
): { text: string; review: ReviewLine[] } {
  const code = options.raw === true ? source : mask(source);
  const edits: Edit[] = [];
  const review: ReviewLine[] = [];

  for (const match of code.matchAll(CALL)) {
    const method = match[1]!;
    const name = match.index + 1;
    const open = match.index + match[0].length - 1;
    const close = closingIndex(code, open);

    if (close === -1) {
      continue;
    }

    const edit = rewrite(source, code, { method, name, open, close });

    if (edit === undefined) {
      review.push({
        line: source.slice(0, name).split("\n").length,
        message: REVIEW,
      });
    } else if (edit !== "skip") {
      edits.push(...edit);
    }
  }

  return { text: apply(source, edits), review };
}

function rewrite(
  source: string,
  code: string,
  call: Call,
): readonly Edit[] | "skip" | undefined {
  const { method, name, open, close } = call;
  const renamed = RENAMED[method];

  if (renamed !== undefined) {
    return [{ start: name, end: name + method.length, text: renamed }];
  }

  const sole = soleArgument(code, open, close);

  if (sole === "several") {
    return method === "exists" ? "skip" : undefined;
  }

  const argument = sole === "none" ? undefined : sole;

  if (method === "exists") {
    // `exists(path)` and `exists({ path })` on a storage or file API are not
    // repository calls; a repository's takes `{ where }` or nothing.
    if (
      argument !== undefined &&
      (code[argument] !== "{" ||
        !properties(source, code, argument)?.some(
          (prop) => prop.key === "where",
        ))
    ) {
      return "skip";
    }

    return [
      { start: name, end: name + method.length, text: "count" },
      { start: close + 1, end: close + 1, text: ".map((n) => n > 0)" },
    ];
  }

  if (method === "findFirst") {
    return findFirst(source, code, call, argument);
  }

  if (argument === undefined || code[argument] !== "{") {
    return undefined;
  }

  const props = properties(source, code, argument);

  if (!props) {
    return undefined;
  }

  const text = (key: string): string | undefined => {
    const prop = props.find((entry) => entry.key === key);

    return prop === undefined
      ? undefined
      : source.slice(prop.valueStart, prop.valueEnd);
  };

  const rest = (...without: string[]): string[] =>
    props
      .filter((prop) => prop.key === undefined || !without.includes(prop.key))
      .map((prop) => source.slice(prop.start, prop.valueEnd));

  const value = text("where");

  if (value === undefined) {
    return undefined;
  }

  const where = value === "where" ? "where" : `where: ${value}`;

  const options = (extra: readonly string[]): string => {
    const items = [...extra];

    return items.length === 0 ? "" : `, { ${items.join(", ")} }`;
  };

  const replace = (verb: string, args: string): Edit[] => [
    { start: name, end: close + 1, text: `${verb}(${args})` },
  ];

  switch (method) {
    case "updateMany": {
      const data = text("data");

      return data === undefined
        ? undefined
        : replace(
            "update",
            `{ ${where} }, ${data}${options(rest("where", "data"))}`,
          );
    }

    case "deleteMany": {
      return replace("delete", `{ ${where} }${options(rest("where"))}`);
    }

    case "findUnique": {
      return replace(
        "get",
        `${value}${options([...rest("where"), "optional: true"])}`,
      );
    }

    case "findOnly": {
      return replace(
        "get",
        `{ ${where} }${options([...rest("where"), "optional: true"])}`,
      );
    }

    default: {
      return undefined;
    }
  }
}

function findFirst(
  source: string,
  code: string,
  call: Call,
  argument: number | undefined,
): readonly Edit[] {
  const { name, open, close } = call;

  const first = {
    start: close + 1,
    end: close + 1,
    text: ".map((rows) => rows[0] ?? null)",
  };

  const verb = { start: name, end: name + "findFirst".length, text: "list" };

  if (argument === undefined) {
    return [verb, { start: open + 1, end: close, text: "{ limit: 1 }" }, first];
  }

  if (code[argument] === "{") {
    const end = closingIndex(code, argument);
    const inner = source.slice(argument + 1, end).trim();

    return [
      verb,
      {
        start: argument,
        end: end + 1,
        text:
          inner.length === 0
            ? "{ limit: 1 }"
            : `{ ${inner.replace(/,\s*$/, "")}, limit: 1 }`,
      },
      first,
    ];
  }

  const value = source.slice(argument, close).trim();

  return [
    verb,
    { start: open + 1, end: close, text: `{ ...${value}, limit: 1 }` },
    first,
  ];
}

/** The index where the only argument starts. */
function soleArgument(
  code: string,
  open: number,
  close: number,
): number | "none" | "several" {
  const start = open + 1 + (/^\s*/.exec(code.slice(open + 1))?.[0].length ?? 0);

  if (start >= close) {
    return "none";
  }

  let depth = 0;

  for (let index = start; index < close; index += 1) {
    const char = code[index]!;

    if (char === '"' || char === "'" || char === "`") {
      index = Math.max(index, code.indexOf(char, index + 1));
    } else if ("({[".includes(char)) {
      depth += 1;
    } else if (")}]".includes(char)) {
      depth -= 1;
    } else if (
      char === "," &&
      depth === 0 &&
      code.slice(index + 1, close).trim() !== ""
    ) {
      return "several";
    }
  }

  return start;
}

function apply(text: string, edits: readonly Edit[]): string {
  let out = "";
  let cursor = 0;

  for (const edit of edits.toSorted((a, b) => a.start - b.start)) {
    if (edit.start < cursor) {
      continue;
    }

    out += text.slice(cursor, edit.start) + edit.text;
    cursor = edit.end;
  }

  return out + text.slice(cursor);
}

/**
 * The data contract moves. 0.15 also renamed `requireTenant` to
 * `requireTenant`; 0.32 renamed it back, so the rewrite leaves it.
 */
export function rewrite015(text: string): {
  readonly text: string;
  readonly review: readonly ReviewLine[];
} {
  return rewriteDataContract(text);
}
