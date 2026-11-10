import type { ReactNode } from "react";

import { RouteMessages } from "@/i18n/route-messages";

export default function OauthLayout({ children }: { children: ReactNode }) {
  return (
    <RouteMessages namespaces={["oauth", "offline"]}>{children}</RouteMessages>
  );
}
