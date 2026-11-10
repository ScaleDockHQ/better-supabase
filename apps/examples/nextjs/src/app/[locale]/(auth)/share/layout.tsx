import type { ReactNode } from "react";

import { RouteMessages } from "@/i18n/route-messages";

export default function ShareLayout({ children }: { children: ReactNode }) {
  return (
    <RouteMessages namespaces={["customers", "offline"]}>
      {children}
    </RouteMessages>
  );
}
