import { CloudIcon } from "lucide-react";

import { OfflineBanner } from "@/features/offline/components/offline-banner";

/**
 * Public pages wider than the sign-in column, such as a status page. Anyone can
 * open them; `src/proxy.ts` lists their paths.
 */
export default function PublicLayout({ children }: LayoutProps<"/[locale]">) {
  return (
    <div className="flex min-h-svh flex-col items-center gap-6 bg-muted/40 p-6">
      <div className="flex items-center gap-2 text-lg font-semibold">
        <span className="flex size-8 items-center justify-center rounded-lg bg-primary text-primary-foreground">
          <CloudIcon className="size-4" />
        </span>
        Acme Cloud
      </div>
      <OfflineBanner className="max-w-3xl" />
      <main className="w-full max-w-3xl">{children}</main>
    </div>
  );
}
