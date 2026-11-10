import type { ReactNode } from "react";

import { RouteMessages } from "@/i18n/route-messages";

export default function IslandsLayout({ children }: { children: ReactNode }) {
  return <RouteMessages namespaces={[]}>{children}</RouteMessages>;
}
