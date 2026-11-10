import type { ReactNode } from "react";

import { RouteMessages } from "@/i18n/route-messages";

export default function BenchLayout({ children }: { children: ReactNode }) {
  return <RouteMessages namespaces={[]}>{children}</RouteMessages>;
}
