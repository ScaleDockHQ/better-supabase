import type { ReactNode } from "react";

import { RouteMessages } from "@/i18n/route-messages";

export default function SendLayout({ children }: { children: ReactNode }) {
  return (
    <RouteMessages namespaces={["drive", "errors", "offline"]}>
      {children}
    </RouteMessages>
  );
}
