import type { ReactNode } from "react";

import { RouteMessages } from "@/i18n/route-messages";

export default function PricingLayout({ children }: { children: ReactNode }) {
  return <RouteMessages namespaces={["offline"]}>{children}</RouteMessages>;
}
