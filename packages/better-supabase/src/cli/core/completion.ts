/**
 * Shell completion. `completion <shell>` prints a script that calls the hidden
 * `__complete` with the words typed so far; `__complete` answers from the
 * command tree and loads only the one command it completes.
 */

import type { ArgDef, ArgsDef } from "citty";

import type { CommandNode } from "./parse.ts";

import { completionValues, GLOBAL_ARGS, listArgs } from "./command.ts";
import { COMPLETE_COMMAND } from "./manifest.ts";
import { commandArgs, isVariadic } from "./parse.ts";

export const SHELLS = ["bash", "zsh", "fish"] as const;

export type Shell = (typeof SHELLS)[number];

export const isShell = (value: string): value is Shell =>
  SHELLS.some((shell) => shell === value);

/** The bins the scripts register for. */
const BINS = ["better-supabase", "bsb"] as const;

/** The line that tells a script to also offer file names. */
const FILES = ":files";

export interface Candidate {
  readonly value: string;
  readonly description?: string;
}

export interface Completion {
  readonly candidates: readonly Candidate[];
  /**
   * The word is a free-form value (a path, a name), so the shell adds file
   * names.
   */
  readonly files: boolean;
}

const NONE: Completion = { candidates: [], files: false };
const FILE_NAMES: Completion = { candidates: [], files: true };

const GLOBALS: ArgsDef = GLOBAL_ARGS;

const takesValue = (definition: ArgDef | undefined): boolean =>
  definition?.type === "string" || definition?.type === "enum";

/** Whether `word` is an option of `args` whose value is the next word. */
const valueFlag = (args: ArgsDef, word: string | undefined): boolean =>
  word?.startsWith("--") === true &&
  !word.includes("=") &&
  takesValue(args[word.slice(2)]);

/** How many of `words` are positionals: not options, and not an option's value. */
const positionalCount = (args: ArgsDef, words: readonly string[]): number =>
  words.filter(
    (word, at) => !word.startsWith("-") && !valueFlag(args, words[at - 1]),
  ).length;

/** The index of the first word that is not an option or a global option's value. */
const firstWord = (words: readonly string[]): number =>
  words.findIndex(
    (word, at) => !word.startsWith("-") && !valueFlag(GLOBALS, words[at - 1]),
  );

/**
 * Fixed values for an option: an enum's options, or a `valueHint` like
 * `auto|yes|no`.
 */
function fixedValues(definition: ArgDef): readonly string[] | undefined {
  if (definition.type === "enum" && definition.options) {
    return definition.options;
  }

  const hint = "valueHint" in definition ? definition.valueHint : undefined;

  return hint?.includes("|") ? hint.split("|") : undefined;
}

function startingWith(
  candidates: readonly Candidate[],
  prefix: string,
): Candidate[] {
  return candidates.filter((candidate) => candidate.value.startsWith(prefix));
}

function optionCandidates(args: ArgsDef): Candidate[] {
  return Object.entries(args).flatMap(([name, definition]) =>
    definition.type === "positional"
      ? []
      : [
          {
            value: `--${name}`,
            ...(definition.description
              ? { description: definition.description }
              : {}),
          },
        ],
  );
}

/** The values for one argument, with `typed` the part of the word they replace. */
function valueCompletion(
  definition: ArgDef,
  hook: (() => readonly string[]) | undefined,
  typed: string,
  list: boolean,
  prefix = "",
): Completion {
  const values = hook?.() ?? fixedValues(definition);

  if (!values) {
    return FILE_NAMES;
  }

  const comma = list ? typed.lastIndexOf(",") : -1;
  const head = typed.slice(0, comma + 1);
  const chosen = new Set(head.split(",").filter(Boolean));

  return {
    candidates: startingWith(
      values
        .filter((value) => !chosen.has(value))
        .map((value) => ({ value: `${prefix}${head}${value}` })),
      `${prefix}${typed}`,
    ),
    files: false,
  };
}

/**
 * The candidates for the last of `words` (the words after the bin, the last one
 * being typed, possibly empty).
 */
export async function complete(
  tree: ReadonlyMap<string, CommandNode>,
  words: readonly string[],
): Promise<Completion> {
  const current = words.at(-1) ?? "";
  const before = words.slice(0, -1);
  let children: ReadonlyMap<string, CommandNode> = tree;
  let node: CommandNode | undefined;
  let rest: readonly string[] = before;

  for (;;) {
    const index = firstWord(rest);

    if (index === -1) {
      break;
    }

    const child = children.get(rest[index] ?? "");

    if (!child) {
      if (!node?.load) {
        return NONE;
      }

      break;
    }

    node = child;
    children = child.children;
    rest = rest.slice(index + 1);
  }

  const command = node?.load ? await node.load() : undefined;
  const own = command ? await commandArgs(command) : {};
  const args: ArgsDef = { ...own, ...GLOBALS };
  const hooks = command ? completionValues(command) : {};
  const lists = new Set(command ? listArgs(command) : []);
  const previous = before.at(-1);
  const previousName = previous?.startsWith("--") ? previous.slice(2) : "";

  if (valueFlag(args, previous)) {
    const definition = args[previousName];

    if (definition) {
      return valueCompletion(
        definition,
        hooks[previousName],
        current,
        lists.has(previousName),
      );
    }
  }

  if (current.startsWith("--") && current.includes("=")) {
    const name = current.slice(2, current.indexOf("="));
    const definition = args[name];

    return definition && takesValue(definition)
      ? valueCompletion(
          definition,
          hooks[name],
          current.slice(name.length + 3),
          lists.has(name),
          `--${name}=`,
        )
      : NONE;
  }

  if (current.startsWith("-")) {
    return {
      candidates: startingWith(
        [
          ...optionCandidates(args),
          { value: "--help", description: "Show help" },
          ...(node
            ? []
            : [{ value: "--version", description: "Show the version" }]),
        ],
        current,
      ),
      files: false,
    };
  }

  if (children.size > 0) {
    return {
      candidates: startingWith(
        [...children.values()].map((child) => ({
          value: child.spec.name,
          description: child.spec.description,
        })),
        current,
      ),
      files: false,
    };
  }

  const positionals = Object.entries(own).filter(
    ([, definition]) => definition.type === "positional",
  );

  const given = positionalCount(args, rest);
  const last = positionals.at(-1);

  const entry =
    positionals[given] ?? (last && isVariadic(last[1]) ? last : undefined);

  if (!entry) {
    return NONE;
  }

  const [name, definition] = entry;
  const hook = hooks[name];

  return hook ? valueCompletion(definition, hook, current, false) : FILE_NAMES;
}

/**
 * `__complete` output: one `value<TAB>description` line per candidate, then
 * `:files` when file names fit.
 */
export function completionLines(completion: Completion): string {
  return [
    ...completion.candidates.map((candidate) =>
      candidate.description
        ? `${candidate.value}\t${candidate.description}`
        : candidate.value,
    ),
    ...(completion.files ? [FILES] : []),
  ].join("\n");
}

const BASH = `# better-supabase completion for bash. Add to ~/.bashrc:
#   eval "$(better-supabase completion bash)"
_better_supabase_complete() {
  local cur="\${COMP_WORDS[COMP_CWORD]}" line files=0 i
  local -a args=()
  # Bash 3.2 joins a quoted array slice into one word once IFS changes.
  for ((i = 1; i <= COMP_CWORD; i++)); do
    args+=("\${COMP_WORDS[i]}")
  done
  local IFS=$'\\n'
  COMPREPLY=()
  for line in $("\${COMP_WORDS[0]}" ${COMPLETE_COMMAND} -- "\${args[@]}" 2>/dev/null); do
    if [[ $line == "${FILES}" ]]; then
      files=1
    else
      COMPREPLY+=("\${line%%$'\\t'*}")
    fi
  done
  if [[ $files == 1 ]]; then
    compopt -o filenames 2>/dev/null
    COMPREPLY+=($(compgen -f -- "$cur"))
  fi
}
complete -F _better_supabase_complete ${BINS.join(" ")}
`;

const ZSH = `#compdef ${BINS.join(" ")}
# better-supabase completion for zsh. Add to ~/.zshrc:
#   eval "$(better-supabase completion zsh)"
_better_supabase() {
  local -a values
  local line files=0
  for line in "\${(@f)$("\${words[1]}" ${COMPLETE_COMMAND} -- "\${(@)words[2,CURRENT]}" 2>/dev/null)}"; do
    if [[ $line == "${FILES}" ]]; then
      files=1
    elif [[ $line == *$'\\t'* ]]; then
      values+=("\${\${line%%$'\\t'*}//:/\\\\:}:\${line#*$'\\t'}")
    elif [[ -n $line ]]; then
      values+=("\${line//:/\\\\:}")
    fi
  done
  (( \${#values} )) && _describe -t values better-supabase values
  (( files )) && _files
}
if [[ \${zsh_eval_context[-1]} == loadautofunc ]]; then
  _better_supabase "$@"
else
  compdef _better_supabase ${BINS.join(" ")}
fi
`;

const FISH = `# better-supabase completion for fish. Add to ~/.config/fish/config.fish:
#   better-supabase completion fish | source
function __better_supabase_complete
    set -l words (commandline -opc) (commandline -ct)
    for line in ($words[1] ${COMPLETE_COMMAND} -- $words[2..-1] 2>/dev/null)
        if test "$line" = "${FILES}"
            __fish_complete_path (commandline -ct)
        else
            echo $line
        end
    end
end
${BINS.map((bin) => `complete -c ${bin} -f -a '(__better_supabase_complete)'`).join("\n")}
`;

/** The script that registers completion for both bins in `shell`. */
export function completionScript(shell: Shell): string {
  switch (shell) {
    case "bash": {
      return BASH;
    }

    case "zsh": {
      return ZSH;
    }

    case "fish": {
      return FISH;
    }

    default: {
      const unknown: never = shell;

      return unknown;
    }
  }
}
