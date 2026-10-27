import { forbidden } from "next/navigation";

/**
 * The proxy rewrites a page the token's permissions rule out to this path, so
 * `forbidden.tsx` renders with a 403 before the page reads anything.
 */
export default function ForbiddenPage(): never {
  forbidden();
}
