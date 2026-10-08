import "server-only";

/**
 * A `fetch` that waits `ms` before each request, to make every Supabase
 * round trip from the server visible. Cached reads and the static shell
 * skip it, so a slow page under it shows which reads were not cached.
 */
function delayedFetch(ms: number): typeof fetch {
  return async (input, init) => {
    await new Promise<void>((resolve, reject) => {
      const signal = init?.signal;
      const timer = setTimeout(resolve, ms);
      signal?.addEventListener(
        "abort",
        () => {
          clearTimeout(timer);
          reject(
            signal.reason instanceof Error
              ? signal.reason
              : new Error("Aborted"),
          );
        },
        { once: true },
      );
    });
    return fetch(input, init);
  };
}

const delayMs = Number(process.env["BS_FETCH_DELAY_MS"] ?? "0");

if (delayMs > 0) {
  console.warn(
    `BS_FETCH_DELAY_MS=${String(delayMs)}: every Supabase request from this server waits ${String(delayMs)} ms. Never set it in production.`,
  );
}

/** Set only when `BS_FETCH_DELAY_MS` is (the e2e `latency` project). */
export const serverFetch: typeof fetch | undefined =
  delayMs > 0 ? delayedFetch(delayMs) : undefined;
