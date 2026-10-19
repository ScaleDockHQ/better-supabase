import { CliError } from "./errors.ts";
import { positionalIndex } from "./parse.ts";

interface MovedCommand {
  readonly from: readonly string[];
  readonly to: readonly string[];
}

/** Commands renamed in 0.9, longest prefix first. */
const MOVED_COMMANDS: readonly MovedCommand[] = [
  { from: ["openapi", "emit"], to: ["spec", "emit", "openapi"] },
  { from: ["openapi"], to: ["spec", "emit", "openapi"] },
  { from: ["spec", "check"], to: ["spec", "emit", "--check"] },
];

/** Flags renamed in 0.9, by command path. A replacement with a space takes no value from argv. */
const MOVED_FLAGS: ReadonlyMap<
  string,
  Readonly<Record<string, string>>
> = new Map([
  ["init", { with: "integration" }],
  ["add", { framework: "integration" }],
  ["adopt", { from: "tables" }],
  ["gen", { tasks: "only", out: "out-dir" }],
  ["introspect", { format: "kind" }],
  ["doctor", { strict: "fail-on warning" }],
  ["env", { print: "out -", from: "status-file" }],
  ["skills list", { from: "source" }],
  ["skills install", { from: "source", agent: "for" }],
  ["sql add", { force: "allow-hook-overlap" }],
]);

/** `argv` without the words of `prefix`, or `undefined` when it doesn't start with them. */
function withoutPrefix(
  argv: readonly string[],
  prefix: readonly string[],
): string[] | undefined {
  let rest = [...argv];
  let index = positionalIndex(rest);

  for (const part of prefix) {
    if (index === -1 || rest[index] !== part) {
      return undefined;
    }

    rest = rest.toSpliced(index, 1);
    index = positionalIndex(rest, index);
  }

  return rest;
}

function same(a: readonly string[], b: readonly string[]): boolean {
  return a.length === b.length && a.every((word, index) => word === b[index]);
}

/** The flag name of `arg` when it is a long flag, without `--` and any `=value`. */
function flagName(arg: string): string | undefined {
  return arg.startsWith("--") ? arg.slice(2).split("=")[0] : undefined;
}

/** `rest` with every flag in `flags` renamed, up to a `--`. */
function renameFlags(
  rest: readonly string[],
  flags: Readonly<Record<string, string>>,
): string[] {
  const end = rest.indexOf("--");
  const options = end === -1 ? rest : rest.slice(0, end);

  return [
    ...options.flatMap((arg) => {
      const name = flagName(arg);

      if (name === undefined || !Object.hasOwn(flags, name)) {
        return [arg];
      }

      const [, value] = arg.slice(2).split(/[=](.*)/su);
      const replacement = flags[name] ?? name;

      if (replacement.includes(" ")) {
        return replacement
          .split(" ")
          .map((word, index) => (index === 0 ? `--${word}` : word));
      }

      return [`--${replacement}${value === undefined ? "" : `=${value}`}`];
    }),
    ...(end === -1 ? [] : rest.slice(end)),
  ];
}

/**
 * The 0.9 spelling of a CLI call's arguments (the words after the bin), or
 * `undefined` when nothing in it moved. Codemods use it to rewrite scripts.
 */
export function migrateCliCall(argv: readonly string[]): string[] | undefined {
  let next = [...argv];

  for (const moved of MOVED_COMMANDS) {
    const rest = withoutPrefix(next, moved.from);

    if (rest) {
      next = [...moved.to, ...rest];
      break;
    }
  }

  const paths = [...MOVED_FLAGS.keys()].toSorted(
    (a, b) => b.split(" ").length - a.split(" ").length,
  );

  for (const path of paths) {
    const parts = path.split(" ");
    const rest = withoutPrefix(next, parts);

    if (rest) {
      const renamed = renameFlags(rest, MOVED_FLAGS.get(path) ?? {});

      if (!same(renamed, rest)) {
        next = [...parts, ...renamed];
      }

      break;
    }
  }

  return same(next, argv) ? undefined : next;
}

/** A `command_moved` error when `argv` starts with a renamed command. */
export function movedCommand(
  argv: readonly string[],
  bin = "better-supabase",
): CliError | undefined {
  for (const moved of MOVED_COMMANDS) {
    const rest = withoutPrefix(argv, moved.from);

    if (rest) {
      const next = [bin, ...moved.to, ...rest].join(" ");

      return new CliError(
        "command_moved",
        `"${moved.from.join(" ")}" is now "${moved.to.join(" ")}". Run: ${next}`,
        { suggestion: next },
      );
    }
  }

  return undefined;
}

/** A `command_moved` error when `rest` (the argv after the command path) passes a renamed flag. */
export function movedFlag(
  path: readonly string[],
  rest: readonly string[],
  bin = "better-supabase",
): CliError | undefined {
  const flags = MOVED_FLAGS.get(path.join(" "));

  if (!flags) {
    return undefined;
  }

  const end = rest.indexOf("--");
  const options = end === -1 ? rest : rest.slice(0, end);

  const index = options.findIndex((arg) => {
    const name = flagName(arg);

    return name !== undefined && Object.hasOwn(flags, name);
  });

  if (index === -1) {
    return undefined;
  }

  const arg = options[index] ?? "";
  const [name = "", value] = arg.slice(2).split(/[=](.*)/su);
  const replacement = flags[name] ?? name;
  const takesNoValue = replacement.includes(" ");

  const rewritten = [
    ...rest.slice(0, index),
    `--${replacement}${value === undefined || takesNoValue ? "" : `=${value}`}`,
    ...rest.slice(index + 1),
  ];

  const next = [bin, ...path, ...rewritten].join(" ");

  return new CliError(
    "command_moved",
    `--${name} is now --${replacement}. Run: ${next}`,
    { suggestion: next, flag: `--${replacement.split(" ")[0]}` },
  );
}
