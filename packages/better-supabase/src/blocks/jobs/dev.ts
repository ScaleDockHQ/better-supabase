export interface DevDrainOptions {
  readonly url: string | URL;
  readonly secret: string;
  readonly every?: number;
  readonly fetch?: typeof fetch;
  readonly signal?: AbortSignal;
  readonly onError?: (message: string) => void;
}

export interface DevDrain {
  tick(): Promise<void>;
  stop(): void;
}

export function devDrainSecret(
  env: Record<string, string | undefined>,
  name = "CRON_SECRET",
): string {
  const current = env[name];
  if (current) return current;
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  const secret = Array.from(bytes, (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
  env[name] = secret;
  return secret;
}

export function devDrain(options: DevDrainOptions): DevDrain {
  if (!options.secret) {
    throw new TypeError(
      "devDrain needs the drain route's secret, such as devDrainSecret(process.env)",
    );
  }
  const every = options.every ?? 60_000;
  if (!Number.isFinite(every) || every <= 0) {
    throw new TypeError("devDrain: every must be a positive number of ms");
  }
  const doFetch = options.fetch ?? fetch;
  const report =
    options.onError ??
    ((message: string) => {
      console.warn(message);
    });
  let running = false;
  const tick = async (): Promise<void> => {
    if (running || options.signal?.aborted) return;
    running = true;
    try {
      const response = await doFetch(options.url, {
        headers: { authorization: `Bearer ${options.secret}` },
      });
      await response.body?.cancel();
      if (!response.ok) {
        report(`[jobs] dev drain answered ${String(response.status)}`);
      }
    } catch (cause) {
      report(
        `[jobs] dev drain failed: ${cause instanceof Error ? cause.message : String(cause)}`,
      );
    } finally {
      running = false;
    }
  };
  const timer = setInterval(() => {
    void tick();
  }, every);
  const stop = (): void => {
    clearInterval(timer);
  };
  options.signal?.addEventListener("abort", stop, { once: true });
  return { tick, stop };
}
