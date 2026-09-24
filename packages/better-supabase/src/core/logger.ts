export type LogFields = Readonly<Record<string, unknown>>;

/**
 * Where better-supabase reports problems it swallows on purpose: event
 * handlers, `afterMutation` hooks, sinks and cache adapters that throw.
 * Structured loggers (pino, consola, OpenTelemetry logs) fit directly.
 */
export interface Logger {
  debug(message: string, fields?: LogFields): void;
  info(message: string, fields?: LogFields): void;
  warn(message: string, fields?: LogFields): void;
  error(message: string, fields?: LogFields): void;
}

const log =
  (method: 'debug' | 'info' | 'warn' | 'error') =>
  (message: string, fields?: LogFields): void => {
    if (fields === undefined) console[method](`better-supabase: ${message}`);
    else console[method](`better-supabase: ${message}`, fields);
  };

/** The default: `console`, with a `better-supabase:` prefix. */
export const consoleLogger: Logger = {
  debug: log('debug'),
  info: log('info'),
  warn: log('warn'),
  error: log('error'),
};

const noop = (): void => {};

export const silentLogger: Logger = {
  debug: noop,
  info: noop,
  warn: noop,
  error: noop,
};
