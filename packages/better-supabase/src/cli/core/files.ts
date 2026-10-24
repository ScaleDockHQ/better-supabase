import { chmod, mkdir, rename, rm, writeFile } from "node:fs/promises";
import { dirname, isAbsolute, relative, resolve, sep } from "node:path";

import type { Paint } from "../style.ts";
import type { CommandResult } from "./io.ts";

import { blockFileState } from "../../sql/index.ts";
import { fileDiff } from "../diff.ts";
import { plain } from "../style.ts";
import { CliError } from "./errors.ts";
import { display, readIfExists, sameText } from "./io.ts";

/**
 * `path` resolved under `root`, or an error when it leaves the root (an
 * absolute path elsewhere, or one that climbs out with `..`).
 */
export function insideRoot(root: string, path: string, flag: string): string {
  const resolved = resolve(root, path);
  const inside = relative(root, resolved);

  if (inside === ".." || inside.startsWith(`..${sep}`) || isAbsolute(inside)) {
    throw new CliError(
      "outside_root",
      `${flag} ${path} is outside the project root ${root}. Run the command from the project that owns the file.`,
      { flag },
    );
  }

  return resolved;
}

/**
 * How a planned file treats one that is already on disk:
 *
 * - `generated`: rewritten whenever its contents change.
 * - `owned`: rewritten only while it carries the better-supabase header, so a
 *   file the app wrote by hand is skipped unless `--force` is set.
 * - `create`: written once; an existing file belongs to the app and is skipped
 *   unless `--force` is set.
 * - `edit`: an app file the command rewrites in place (a codemod, a config edit).
 *   It must exist.
 * - `block`: a block schema, data or test file. Rewritten while its `@bsb-hash`
 *   matches the body or the file has no hash yet. A body that no longer matches
 *   its hash was edited by hand and is skipped unless `--force` is set.
 */
export type FilePolicy = "generated" | "owned" | "create" | "edit" | "block";

/**
 * Why a block file was left alone. The same text is the skip reason and the
 * command error.
 */
export const HAND_EDITED =
  "edited by hand; move the change to an override file or SQL hook, or pass --force";

/** The command error for block files left alone because they were edited. */
export function handEditedError(files: readonly string[]): string {
  return `${files.join(", ")} ${files.length === 1 ? "was" : "were"} edited by hand, so the CLI left ${files.length === 1 ? "it" : "them"} alone. Move the change to an override file or a SQL hook, or pass --force.`;
}

/**
 * A reason to keep a block file that would otherwise be removed, when its body
 * no longer matches its hash.
 */
export function keepHandEdit(current: string): string | undefined {
  return blockFileState(current) === "edited" ? HAND_EDITED : undefined;
}

export interface PlannedFile {
  /** Relative to the plan's root, or absolute inside it. */
  readonly path: string;
  readonly contents: string;
  /**
   * Defaults to `owned` when the contents carry the better-supabase header,
   * else `generated`.
   */
  readonly policy?: FilePolicy;
  readonly mode?: number;
  /** Shown after the path, like the module that renders the file. */
  readonly note?: string;
  /**
   * The file holds secrets, so `--dry-run` and `--check` name it without a
   * diff.
   */
  readonly secret?: boolean;
  /**
   * Whether the file on disk already matches. Defaults to the text, ignoring
   * line endings.
   */
  readonly same?: (current: string, contents: string) => boolean;
}

/** The files a command creates, updates, skips or removes. The core applies it. */
export interface FilePlan {
  readonly root: string;
  readonly files: readonly PlannedFile[];
  /**
   * Generated files that are no longer generated, relative to the root. An
   * object can refuse the removal: `keep` returns the skip reason.
   */
  readonly remove?: readonly Removal[];
  /** The command that rewrites the files, named when `--check` finds drift. */
  readonly regenerate: string;
  /** Paths are shown relative to this directory. Defaults to the root. */
  readonly base?: string;
}

/** A path to remove, or one kept when `keep` returns a reason. */
export type Removal =
  | string
  | {
      readonly path: string;
      readonly keep?: (current: string) => string | undefined;
    };

export type FileOutcome = "create" | "update" | "unchanged" | "skip" | "remove";

export interface FileChange {
  /** The path shown to people, with forward slashes. */
  readonly file: string;
  readonly outcome: FileOutcome;
  readonly note?: string;
  /** Why a file was skipped. */
  readonly reason?: string;
}

/** The flags every writing command takes. */
export interface PlanFlags {
  readonly "dry-run"?: boolean | undefined;
  readonly check?: boolean | undefined;
  readonly force?: boolean | undefined;
}

/** `--dry-run`, `--check` and `--force`, for a command's `args`. */
export const PLAN_ARGS = {
  "dry-run": {
    type: "boolean",
    description: "Print what would change, with a diff, and write nothing",
  },
  check: {
    type: "boolean",
    description: "Write nothing; exit 1 with a diff when a file would change",
  },
  force: {
    type: "boolean",
    description: "Overwrite files the CLI did not generate",
  },
} as const;

export interface AppliedPlan {
  readonly mode: "write" | "dry-run" | "check";
  readonly changes: readonly FileChange[];
  /**
   * Unified diffs of every create, update and removal, and of each file skipped
   * as written by hand.
   */
  readonly diffs: readonly string[];
  /** Whether a file would be created, updated or removed. */
  readonly drift: boolean;
}

const HEADER = /generated by `?better-supabase/i;

/** Whether `text` carries the better-supabase header in its first lines. */
export function ownedByUs(text: string): boolean {
  return HEADER.test(text.split("\n", 5).join("\n"));
}

const FORCE_HINT = "pass --force to overwrite";
const NOT_OURS = `not generated by better-supabase; ${FORCE_HINT}`;

const KEPT = new Set([NOT_OURS, HAND_EDITED]);

/** Whether the plan skipped a file it will not overwrite without `--force`. */
export const hasConflicts = (applied: AppliedPlan): boolean =>
  applied.changes.some(
    ({ reason }) => reason !== undefined && KEPT.has(reason),
  );

function outcomeOf(
  file: PlannedFile,
  current: string | undefined,
  force: boolean,
): { readonly outcome: FileOutcome; readonly reason?: string } {
  const policy =
    file.policy ?? (ownedByUs(file.contents) ? "owned" : "generated");

  if (current === undefined) {
    return policy === "edit"
      ? { outcome: "skip", reason: "missing" }
      : { outcome: "create" };
  }

  if (
    file.same
      ? file.same(current, file.contents)
      : sameText(current, file.contents)
  ) {
    return { outcome: "unchanged" };
  }

  if (force) {
    return { outcome: "update" };
  }

  switch (policy) {
    case "generated":
    case "edit": {
      return { outcome: "update" };
    }

    case "owned": {
      return ownedByUs(current)
        ? { outcome: "update" }
        : { outcome: "skip", reason: NOT_OURS };
    }

    case "create": {
      return { outcome: "skip", reason: `exists; ${FORCE_HINT}` };
    }

    case "block": {
      return blockFileState(current) === "edited"
        ? { outcome: "skip", reason: HAND_EDITED }
        : { outcome: "update" };
    }

    default: {
      const unknown: never = policy;

      return unknown;
    }
  }
}

interface Staged {
  readonly path: string;
  readonly contents: string;
  readonly mode: number | undefined;
}

/**
 * Writes every file next to its target first, then renames them all, so a
 * failed write leaves no file half written.
 */
async function writeAll(files: readonly Staged[]): Promise<void> {
  const temporary = files.map(
    (file, index) => `${file.path}.${process.pid}.${index}.tmp`,
  );

  try {
    for (const [index, file] of files.entries()) {
      await mkdir(dirname(file.path), { recursive: true });
      await writeFile(
        temporary[index] ?? file.path,
        file.contents,
        file.mode === undefined ? {} : { mode: file.mode },
      );
    }
  } catch (error) {
    await Promise.all(
      temporary.map((path) => rm(path, { force: true }).catch(() => undefined)),
    );

    throw error;
  }

  for (const [index, file] of files.entries()) {
    await rename(temporary[index] ?? file.path, file.path);

    if (file.mode !== undefined) {
      await chmod(file.path, file.mode);
    }
  }
}

/**
 * Applies `plan`: checks every path stays inside the root, decides what happens
 * to each file, then writes nothing (`--dry-run`, `--check`) or writes every
 * change at once.
 */
export async function applyPlan(
  plan: FilePlan,
  flags: PlanFlags,
  paint: Paint = plain,
): Promise<AppliedPlan> {
  const mode =
    flags.check === true
      ? "check"
      : flags["dry-run"] === true
        ? "dry-run"
        : "write";

  const force = flags.force === true;
  const base = plan.base ?? plan.root;
  const changes: FileChange[] = [];
  const diffs: string[] = [];
  const staged: Staged[] = [];
  const modes: { readonly path: string; readonly mode: number }[] = [];
  const seen = new Set<string>();

  for (const file of plan.files) {
    const path = insideRoot(plan.root, file.path, "path");

    if (seen.has(path)) {
      continue;
    }

    seen.add(path);
    const shown = display(base, path);
    const current = await readIfExists(path);
    const { outcome, reason } = outcomeOf(file, current, force);

    changes.push({
      file: shown,
      outcome,
      ...(file.note ? { note: file.note } : {}),
      ...(reason ? { reason } : {}),
    });

    const conflict = reason !== undefined && KEPT.has(reason);

    if (outcome === "create" || outcome === "update" || conflict) {
      diffs.push(
        file.secret === true
          ? `${shown} would change (the diff is hidden: the file holds secrets).`
          : fileDiff(shown, current, file.contents, paint),
      );
    }

    if (outcome === "create" || outcome === "update") {
      staged.push({ path, contents: file.contents, mode: file.mode });
    } else if (outcome === "unchanged" && file.mode !== undefined) {
      modes.push({ path, mode: file.mode });
    }
  }

  const removed: string[] = [];

  for (const entry of plan.remove ?? []) {
    const item = typeof entry === "string" ? { path: entry } : entry;
    const path = insideRoot(plan.root, item.path, "path");
    const current = await readIfExists(path);

    if (current === undefined) {
      continue;
    }

    const shown = display(base, path);

    const reason =
      force || item.keep === undefined ? undefined : item.keep(current);

    if (reason !== undefined) {
      changes.push({ file: shown, outcome: "skip", reason });
      diffs.push(fileDiff(shown, current, "", paint));
      continue;
    }

    changes.push({ file: shown, outcome: "remove" });
    diffs.push(fileDiff(shown, current, "", paint));
    removed.push(path);
  }

  if (mode === "write") {
    await writeAll(staged);

    for (const path of removed) {
      await rm(path, { force: true });
    }

    for (const { path, mode: fileMode } of modes) {
      await chmod(path, fileMode);
    }
  }

  return {
    mode,
    changes,
    diffs,
    drift: staged.length > 0 || removed.length > 0,
  };
}

const VERB: Readonly<Record<FileOutcome, readonly [string, string]>> = {
  create: ["Created", "Would create"],
  update: ["Updated", "Would update"],
  remove: ["Removed", "Would remove"],
  unchanged: ["Unchanged", "Unchanged"],
  skip: ["Skipped", "Skipped"],
};

/**
 * One `Created`, `Updated`, `Skipped`, `Unchanged` or `Would create` line per
 * file.
 */
export function changeLines(applied: AppliedPlan): string[] {
  return applied.changes.map(({ file, outcome, note, reason }) => {
    const [done, planned] = VERB[outcome];
    const verb = applied.mode === "write" ? done : planned;
    const extra = [note, reason].filter(Boolean).join("; ");

    return `${verb} ${file}${extra ? ` (${extra})` : ""}`;
  });
}

/** The files a plan changed, for `data.files`. */
export const changedFiles = (applied: AppliedPlan): string[] =>
  applied.changes
    .filter(
      ({ outcome }) =>
        outcome === "create" || outcome === "update" || outcome === "remove",
    )
    .map(({ file }) => file);

/**
 * The result of an applied plan. `--check` fails with the diffs when a file
 * would change; `--dry-run` prints the diffs and the lines; a write prints the
 * lines. `summary` follows the lines, and `data` joins `data.files`.
 */
export function planResult(
  plan: FilePlan,
  applied: AppliedPlan,
  options: {
    readonly summary?: string;
    readonly data?: Readonly<Record<string, unknown>>;
  } = {},
): CommandResult {
  const data = {
    ...options.data,
    files: applied.changes,
    ...(applied.mode === "write"
      ? {}
      : { upToDate: !applied.drift && !hasConflicts(applied) }),
  };

  const lines = changeLines(applied);

  const text = [...lines, ...(options.summary ? [options.summary] : [])].join(
    "\n",
  );

  const conflicts = applied.changes.filter(
    ({ reason }) => reason !== undefined && KEPT.has(reason),
  );

  if (conflicts.length > 0) {
    const owned = conflicts.filter(({ reason }) => reason === NOT_OURS);
    const edited = conflicts.filter(({ reason }) => reason === HAND_EDITED);

    const error = [
      owned.length === 0
        ? undefined
        : `${owned.map(({ file }) => file).join(", ")} ${owned.length === 1 ? "was" : "were"} not generated by better-supabase, so the CLI left ${owned.length === 1 ? "it" : "them"} alone. Pass --force to overwrite.`,
      edited.length === 0
        ? undefined
        : handEditedError(edited.map(({ file }) => file)),
    ]
      .filter((line) => line !== undefined)
      .join(" ");

    return {
      code: 1,
      output: [...(applied.mode === "write" ? [] : applied.diffs), text]
        .filter(Boolean)
        .join("\n\n"),
      error,
      errorCode: "file_conflict",
      data,
    };
  }

  if (applied.mode === "check") {
    if (!applied.drift) {
      return {
        code: 0,
        output:
          applied.changes.length === 1
            ? `${applied.changes[0]?.file} is up to date.`
            : `${applied.changes.length} files are up to date.`,
        data,
      };
    }

    const stale = changedFiles(applied);

    return {
      code: 1,
      output: applied.diffs.join("\n\n"),
      error: `${stale.length === 1 ? `${stale[0]} is` : `${stale.length} files are`} out of date. Run \`${plan.regenerate}\`.`,
      errorCode: "check_failed",
      next: [{ command: plan.regenerate, when: "rewrites the files" }],
      data,
    };
  }

  if (applied.mode === "dry-run") {
    return {
      code: 0,
      output: [...applied.diffs, text].filter(Boolean).join("\n\n"),
      data,
    };
  }

  return { code: 0, output: text, data };
}
