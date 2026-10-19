import type { Paint } from "../style.ts";

/**
 * Messages for the person running the command. Every method writes to
 * stderr, so stdout carries only the command's output or its JSON document.
 */
export interface CliLog {
  readonly info: (text: string) => void;
  readonly warn: (text: string) => void;
  readonly error: (text: string) => void;
  /** Written only under `--debug`. */
  readonly debug: (text: string) => void;
  /**
   * Runs `task` while `message` shows: a spinner on a terminal, one plain
   * line elsewhere. Under `--debug` it also logs how long the task took.
   */
  readonly progress: <T>(message: string, task: () => Promise<T>) => Promise<T>;
}

export interface LogOptions {
  /** Writes one line to stderr; the line ends in `\n`. */
  readonly write: (line: string) => void;
  readonly paint: Paint;
  readonly debug: boolean;
  /** Shows `message` until the returned function is called. Without it, progress shows nothing. */
  readonly spinner?: (message: string) => () => void;
  readonly now?: () => number;
}

export const milliseconds = (start: number, end: number): string =>
  `${Math.round(end - start)}ms`;

export function createLog(options: LogOptions): CliLog {
  const { write, paint, debug, spinner } = options;
  const now = options.now ?? (() => performance.now());

  const line = (text: string): void => {
    write(text.endsWith("\n") ? text : `${text}\n`);
  };

  return {
    info: line,
    warn: (text) => {
      line(`${paint("yellow", "Warning:")} ${text}`);
    },
    error: (text) => {
      line(paint("red", text));
    },
    debug: (text) => {
      if (debug) {
        line(paint("dim", `debug ${text}`));
      }
    },
    progress: async (message, task) => {
      const stop = spinner?.(message);
      const start = now();

      try {
        return await task();
      } finally {
        stop?.();

        if (debug) {
          line(paint("dim", `debug ${message}: ${milliseconds(start, now())}`));
        }
      }
    },
  };
}
