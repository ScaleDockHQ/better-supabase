/** A finished child process, published on {@link EXEC_CHANNEL} for `--debug`. */
export interface ExecEvent {
  readonly command: string;
  readonly args: readonly string[];
  readonly cwd: string;
  readonly code: number;
  readonly milliseconds: number;
}

/** The `node:diagnostics_channel` name the CLI publishes each child process on. */
export const EXEC_CHANNEL = "better-supabase:exec";
