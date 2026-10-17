/**
 * Imports an optional peer package on first use, or resolves `undefined` when
 * it is not installed so the caller can say how to add it. The specifier is
 * a variable on purpose: bundlers then leave the peer out of apps that never
 * reach this call.
 */
export async function importOptionalPeer(specifier: string): Promise<unknown> {
  try {
    return await import(specifier);
  } catch {
    return undefined;
  }
}

/** Runs `load` once and shares the promise. A rejection is not kept, so the next call tries again. */
export function memoized<T>(load: () => Promise<T>): () => Promise<T> {
  let promise: Promise<T> | undefined;

  return () =>
    (promise ??= load().catch((cause: unknown) => {
      promise = undefined;
      throw cause;
    }));
}
