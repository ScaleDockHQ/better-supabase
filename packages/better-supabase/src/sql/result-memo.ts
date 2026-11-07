import { stableKey } from "./pipeline/render-key.ts";

/**
 * Where `memoized` keeps results between runs. The CLI installs one that reads
 * and writes files, so `src/sql` stays free of Node built-ins.
 */
export interface MemoBackend {
  /** What the generator is: its version and a hash of its files. */
  readonly salt: string;
  readonly get: (namespace: string, key: string) => unknown;
  readonly set: (namespace: string, key: string, value: unknown) => void;
}

interface MemoState {
  backend: MemoBackend | undefined;
  readonly held: Map<string, unknown>;
  readonly stats: { memory: number; stored: number; computed: number };
}

const STATE_KEY: unique symbol = Symbol.for("better-supabase.result-memo");

// The bundle can hold this module twice (the `./sql` entry and the CLI chunks),
// so the state lives on `globalThis`, where both copies find the same one.
// SAFETY: only this module writes STATE_KEY on globalThis, and it writes a MemoState.
const shared = globalThis as { [STATE_KEY]?: MemoState };

shared[STATE_KEY] ??= {
  backend: undefined,
  held: new Map(),
  stats: { memory: 0, stored: 0, computed: 0 },
};

const state: MemoState = shared[STATE_KEY];

/**
 * Counts for tests and the bench: results found in memory, on disk, or
 * computed.
 */
export const memoStats: MemoState["stats"] = state.stats;

/**
 * Installs the store `memoized` reads and writes, or removes it. Results held
 * in memory stay valid either way, since the key covers the whole input.
 */
export function setMemoBackend(next: MemoBackend | undefined): void {
  state.backend = next;
}

/** Forgets the results held in memory. */
export function clearMemo(): void {
  state.held.clear();
}

/**
 * `compute()` once per `parts`: from memory, then from the installed store,
 * then fresh. `parts` must hold everything the result depends on besides the
 * generator itself; a part with a function makes the call compute every time.
 * `accept` checks a stored value before it is used, so a file from another
 * release or a damaged one is computed again.
 */
export function memoized<T>(
  namespace: string,
  parts: unknown,
  accept: (value: unknown) => value is T,
  compute: () => T,
): T {
  const key = stableKey([namespace, state.backend?.salt ?? "", parts]);

  if (key === undefined) {
    memoStats.computed += 1;

    return compute();
  }

  const id = `${namespace}:${key}`;

  if (state.held.has(id)) {
    memoStats.memory += 1;

    // SAFETY: only values `accept` took or `compute` returned are held under an id.
    return state.held.get(id) as T;
  }

  const stored = state.backend?.get(namespace, key);

  if (stored !== undefined && accept(stored)) {
    memoStats.stored += 1;
    state.held.set(id, stored);

    return stored;
  }

  memoStats.computed += 1;
  const value = compute();
  state.held.set(id, value);
  state.backend?.set(namespace, key, value);

  return value;
}
