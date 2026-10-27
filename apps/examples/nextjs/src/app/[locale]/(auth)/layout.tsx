import { CloudIcon } from "lucide-react";

import { OfflineBanner } from "@/features/offline/components/offline-banner";

/**
 * Synchronous: the brand and the centered column are the static shell. The
 * brand is not a link: a signed-out prefetch of `/` caches the redirect to
 * sign-in, and `refresh()` after signing in doesn't clear it, so the next
 * `router.push("/")` would land back here.
 */
export default function AuthLayout({ children }: LayoutProps<"/[locale]">) {
  return (
    <div className="flex min-h-svh flex-col items-center justify-center gap-6 bg-muted/40 p-6">
      <div className="flex items-center gap-2 text-lg font-semibold">
        <span className="flex size-8 items-center justify-center rounded-lg bg-primary text-primary-foreground">
          <CloudIcon className="size-4" />
        </span>
        Acme Cloud
      </div>
      <OfflineBanner className="max-w-sm" />
      <div className="w-full max-w-sm">{children}</div>
    </div>
  );
}
