import type { ReactNode } from "react";

import { RouteMessages } from "@/i18n/route-messages";

export default function BookLayout({ children }: { children: ReactNode }) {
  return (
    <RouteMessages namespaces={["bookings", "errors", "offline"]}>
      {children}
    </RouteMessages>
  );
}
