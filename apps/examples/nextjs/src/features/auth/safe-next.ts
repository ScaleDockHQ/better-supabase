/**
 * The `?next=` path the proxy put on the sign-in URL, or `fallback`. Only
 * same-origin paths pass, so the parameter can't send anyone elsewhere.
 * Read at submit time, so the page needs no `useSearchParams` boundary.
 */
export function safeNext(fallback: string): string {
  const next = new URLSearchParams(window.location.search).get("next");
  // Browsers read `/\host` like `//host`, another origin.
  return next && /^\/(?![/\\])/.test(next) ? next : fallback;
}
