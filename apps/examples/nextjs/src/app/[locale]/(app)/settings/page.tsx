import { useLocale } from "next-intl";

import { redirect } from "@/i18n/navigation";

// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function SettingsIndex() {
  const locale = useLocale();

  redirect({ href: "/settings/profile", locale });
}
