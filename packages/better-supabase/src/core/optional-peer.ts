/**
 * Imports an optional peer package on first use, or resolves `undefined` when
 * it is not installed so the caller can say how to add it. The specifier is a
 * variable on purpose, and the bundler-ignore comments keep it a native import
 * in bundled apps: bundlers leave the peer out of apps that never reach this
 * call, and an app that externalizes the package resolves it at runtime.
 */
export async function importOptionalPeer(specifier: string): Promise<unknown> {
  try {
    return await import(
      /* webpackIgnore: true */
      /* @vite-ignore */
      specifier
    );
  } catch {
    return undefined;
  }
}

/**
 * Runs `load` once and shares the promise. A rejection is not kept, so the next
 * call tries again.
 */
export function memoized<T>(load: () => Promise<T>): () => Promise<T> {
  let promise: Promise<T> | undefined;

  return () =>
    (promise ??= load().catch((cause: unknown) => {
      promise = undefined;
      throw cause;
    }));
}
