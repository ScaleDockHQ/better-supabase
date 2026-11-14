import { forbidden } from "next/navigation";

/**
 * The proxy rewrites a page the token's permissions rule out to this path, so
 * `forbidden.tsx` renders with a 403 before the page reads anything.
 */
// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function ForbiddenPage(): never {
  forbidden();
}
