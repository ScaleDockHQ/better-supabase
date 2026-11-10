declare global {
  var bsbExampleSessionCounters: { hits: number; misses: number } | undefined;
}

/**
 * Next.js bundles each route handler apart from the pages, so a server module
 * is evaluated once per bundle and each bundle builds its own server. One
 * counter per process makes `/api/bs-sessions` count the lookups of `bsb` and
 * `bsbShell` together: a miss is a render that verified a token.
 */
export function sharedCounters(): { hits: number; misses: number } {
  globalThis.bsbExampleSessionCounters ??= { hits: 0, misses: 0 };

  return globalThis.bsbExampleSessionCounters;
}
