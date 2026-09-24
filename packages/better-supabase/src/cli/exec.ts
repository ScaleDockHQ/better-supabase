import { spawn } from 'node:child_process';

export interface ExecResult {
  readonly code: number;
  readonly stdout: string;
  readonly stderr: string;
}

export function exec(
  command: string,
  args: readonly string[],
  cwd: string,
): Promise<ExecResult> {
  return new Promise((done) => {
    const child = spawn(command, args, {
      cwd,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk: Buffer) => {
      stdout += chunk.toString();
    });
    child.stderr.on('data', (chunk: Buffer) => {
      stderr += chunk.toString();
    });
    child.on('error', (error) =>
      done({ code: 127, stdout, stderr: error.message }),
    );
    child.on('close', (code) => done({ code: code ?? 1, stdout, stderr }));
  });
}

/** Runs the Supabase CLI: `$SUPABASE_BIN`, then `supabase`, then `npx supabase`. */
export async function supabaseCli(
  args: readonly string[],
  cwd: string,
  env: Readonly<Record<string, string | undefined>>,
): Promise<ExecResult> {
  const result = await exec(env.SUPABASE_BIN ?? 'supabase', args, cwd);
  if (result.code !== 127) return result;
  return exec('npx', ['--yes', 'supabase', ...args], cwd);
}
