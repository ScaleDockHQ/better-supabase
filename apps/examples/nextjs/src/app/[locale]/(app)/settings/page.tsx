import { useLocale } from "next-intl";

import { redirect } from "@/i18n/navigation";

export default function SettingsIndex() {
  const locale = useLocale();

  redirect({ href: "/settings/profile", locale });
}
