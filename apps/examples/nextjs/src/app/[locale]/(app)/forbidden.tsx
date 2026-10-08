import { LockIcon } from "lucide-react";
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

/** `forbidden()`, e.g. from `bs.require()`: signed in, but not allowed. Next answers 403. */
export default function Forbidden() {
  const t = useExtracted("app");
  return (
    <Empty role="alert" className="m-6 border">
      <EmptyHeader>
        <EmptyMedia variant="icon">
          <LockIcon />
        </EmptyMedia>
        <EmptyTitle>{t("You don't have access")}</EmptyTitle>
        <EmptyDescription>
          {t("Ask an admin of this organization for access.")}
        </EmptyDescription>
      </EmptyHeader>
      <EmptyContent>
        <Link href="/" className={buttonVariants()}>
          {t("Back to the dashboard")}
        </Link>
      </EmptyContent>
    </Empty>
  );
}
