import { env } from "@/env";

/** Absolute URL on the public site for a path such as `/docs/cli`. */
export function siteUrl(path = ""): string {
  return new URL(path, env.NEXT_PUBLIC_SITE_URL).toString();
}
