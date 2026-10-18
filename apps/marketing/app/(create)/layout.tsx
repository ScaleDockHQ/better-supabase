import type { ReactElement, ReactNode } from "react";

export default function CreateLayout({
  children,
}: {
  children: ReactNode;
}): ReactElement {
  return <div className="flex w-full flex-1 flex-col">{children}</div>;
}
