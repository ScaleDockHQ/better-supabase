import { x } from "tinyexec";

export interface ExecResult {
  readonly code: number;
  readonly stdout: string;
  readonly stderr: string;
}

async function exec(
  command: string,
  args: readonly string[],
  cwd: string,
): Promise<ExecResult> {
  try {
    const result = await x(command, [...args], {
      nodeOptions: { cwd, stdio: ["ignore", "pipe", "pipe"] },
      throwOnError: false,
    });
    return {
      code: result.exitCode ?? 1,
      stdout: result.stdout,
      stderr: result.stderr,
    };
  } catch (error) {
    return {
      code: 127,
      stdout: "",
      stderr: error instanceof Error ? error.message : String(error),
    };
  }
}

/** Runs the Supabase CLI: `$SUPABASE_BIN`, then `supabase`, then `npx supabase`. */
export async function supabaseCli(
  args: readonly string[],
  cwd: string,
  env: Readonly<Record<string, string | undefined>>,
): Promise<ExecResult> {
  const result = await exec(env["SUPABASE_BIN"] ?? "supabase", args, cwd);
  if (result.code !== 127) return result;
  return exec("npx", ["--yes", "supabase", ...args], cwd);
}
