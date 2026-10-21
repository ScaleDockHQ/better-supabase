import type { CliEnv } from "./env.ts";

import { type RunProcess, runProcess } from "./exec.ts";

export interface SharedMemorySegment {
  readonly id: string;
  /** The process that created the segment. */
  readonly pid: number;
  /** The segment size, when `ipcs` printed it. */
  readonly bytes?: number;
  /** The managed stack whose postmaster holds it, when one does. */
  readonly stackId?: string;
}

export interface SharedMemoryUsage {
  /** False where `ipcs` is missing (Windows), so nothing was read. */
  readonly supported: boolean;
  /** The system-wide segment limit (`kern.sysv.shmmni`, `kernel.shmmni`). */
  readonly limit?: number;
  readonly segments: readonly SharedMemorySegment[];
}

type IpcsRow = Omit<SharedMemorySegment, "stackId">;

const DIGITS = /^\d+$/;

const isDigits = (field: string | undefined): field is string =>
  field !== undefined && DIGITS.test(field);

/**
 * The segments from `ipcs -m -b -p` on macOS (`m <id> <key> <mode> <owner>
 * <group> <segsz> <cpid> <lpid>`, or without `<segsz>` when `-b` is left out)
 * and from `ipcs -m -p` on Linux (`<shmid> <owner> <cpid> <lpid>` under a
 * header).
 */
export function parseIpcs(stdout: string): readonly IpcsRow[] {
  const rows: IpcsRow[] = [];

  for (const line of stdout.split("\n")) {
    const fields = line.trim().split(/\s+/);

    if (fields[0] === "m" && fields.length >= 9) {
      const [, id, , , , , segsz, cpid] = fields;

      if (id !== undefined && isDigits(segsz) && isDigits(cpid)) {
        rows.push({ id, pid: Number(cpid), bytes: Number(segsz) });
      }
    } else if (fields[0] === "m" && fields.length === 8) {
      const [, id, , , , , cpid] = fields;

      if (id !== undefined && isDigits(cpid)) {
        rows.push({ id, pid: Number(cpid) });
      }
    } else if (
      fields.length === 4 &&
      isDigits(fields[0]) &&
      isDigits(fields[2]) &&
      isDigits(fields[3])
    ) {
      rows.push({ id: fields[0], pid: Number(fields[2]) });
    }
  }

  return rows;
}

/**
 * Segment sizes by id from Linux `ipcs -m` (`<key> <shmid> <owner> <perms>
 * <bytes> <nattch>`).
 */
export function parseIpcsSizes(stdout: string): ReadonlyMap<string, number> {
  const sizes = new Map<string, number>();

  for (const line of stdout.split("\n")) {
    const [key, id, , perms, bytes] = line.trim().split(/\s+/);

    if (
      key?.startsWith("0x") === true &&
      isDigits(id) &&
      isDigits(perms) &&
      isDigits(bytes)
    ) {
      sizes.set(id, Number(bytes));
    }
  }

  return sizes;
}

const STACK_DATA_DIR = /[/\\]\.supabase[/\\]stacks[/\\]([0-9a-f]{12,})[/\\]/;

/**
 * The managed stack id in a postmaster's command line (`-D
 * ~/.supabase/stacks/<id>/...`).
 */
export function stackIdOf(command: string): string | undefined {
  return STACK_DATA_DIR.exec(command)?.[1];
}

/** `pid command` lines from `ps -o pid=,command=`. */
export function parsePs(stdout: string): ReadonlyMap<number, string> {
  const commands = new Map<number, string>();

  for (const line of stdout.split("\n")) {
    const match = /^\s*(\d+)\s+(.*)$/.exec(line);

    if (match?.[1] !== undefined && match[2] !== undefined) {
      commands.set(Number(match[1]), match[2]);
    }
  }

  return commands;
}

async function segmentLimit(
  root: string,
  env: CliEnv,
  run: RunProcess,
  platform: NodeJS.Platform,
): Promise<number | undefined> {
  const result =
    platform === "linux"
      ? await run("cat", ["/proc/sys/kernel/shmmni"], root, env)
      : await run("sysctl", ["-n", "kern.sysv.shmmni"], root, env);

  const value = Number(result.stdout.trim());

  return result.code === 0 && Number.isInteger(value) && value > 0
    ? value
    : undefined;
}

async function segmentRows(
  root: string,
  env: CliEnv,
  run: RunProcess,
  platform: NodeJS.Platform,
): Promise<readonly IpcsRow[] | undefined> {
  if (platform !== "linux") {
    const ipcs = await run("ipcs", ["-m", "-b", "-p"], root, env);

    return ipcs.code === 0 ? parseIpcs(ipcs.stdout) : undefined;
  }

  const [pids, sizes] = await Promise.all([
    run("ipcs", ["-m", "-p"], root, env),
    run("ipcs", ["-m"], root, env),
  ]);

  if (pids.code !== 0) {
    return undefined;
  }

  const bytes = parseIpcsSizes(sizes.stdout);

  return parseIpcs(pids.stdout).map((row) => {
    const size = bytes.get(row.id);

    return size === undefined ? row : { ...row, bytes: size };
  });
}

/**
 * The System V shared memory segments in use, each tied to the managed stack
 * whose postmaster created it. Every running Postgres keeps one small segment
 * as an interlock, even with `shared_memory_type = mmap`, so the segment limit
 * caps how many stacks and shadow databases run at once.
 */
export async function readSharedMemory(
  root: string,
  env: CliEnv,
  run: RunProcess = runProcess,
  platform: NodeJS.Platform = process.platform,
): Promise<SharedMemoryUsage> {
  const rows = await segmentRows(root, env, run, platform);

  if (rows === undefined) {
    return { supported: false, segments: [] };
  }

  const limit = await segmentLimit(root, env, run, platform);
  const pids = [...new Set(rows.map((row) => row.pid))];

  const ps =
    pids.length === 0
      ? undefined
      : await run(
          "ps",
          ["-o", "pid=,command=", "-p", pids.join(",")],
          root,
          env,
        );

  const commands =
    ps === undefined ? new Map<number, string>() : parsePs(ps.stdout);

  const segments = rows.map((row): SharedMemorySegment => {
    const command = commands.get(row.pid);
    const stackId = command === undefined ? undefined : stackIdOf(command);

    return stackId === undefined ? row : { ...row, stackId };
  });

  return {
    supported: true,
    ...(limit === undefined ? {} : { limit }),
    segments,
  };
}
