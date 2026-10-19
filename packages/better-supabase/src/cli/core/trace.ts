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

/** A finished HTTP request, published on {@link HTTP_CHANNEL} for `--debug`. */
export interface HttpEvent {
  readonly method: string;
  /** Without credentials: tokens travel in headers, and userinfo is redacted. */
  readonly url: string;
  /** Unset when the request never got a response. */
  readonly status?: number;
  readonly milliseconds: number;
}

/** The `node:diagnostics_channel` name the CLI publishes each HTTP request on. */
export const HTTP_CHANNEL = "better-supabase:http";
