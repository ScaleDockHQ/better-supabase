import { CompassIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import { buttonVariants } from "@/components/ui/button";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Link } from "@/i18n/navigation";

export default function NotFound() {
  const t = useExtracted("app");
  return (
    <main className="flex min-h-svh items-center justify-center p-6">
      <Empty>
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <CompassIcon />
          </EmptyMedia>
          <EmptyTitle>{t("Page not found")}</EmptyTitle>
          <EmptyDescription>
            {t("It moved, or it isn't available to your organization.")}
          </EmptyDescription>
        </EmptyHeader>
        <EmptyContent>
          <Link href="/" className={buttonVariants()}>
            {t("Back to the dashboard")}
          </Link>
        </EmptyContent>
      </Empty>
    </main>
  );
}
