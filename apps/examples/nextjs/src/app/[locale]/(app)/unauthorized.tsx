import { LogInIcon } from "lucide-react";
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

/** `unauthorized()`, e.g. from `bs.require()` without a session. Next answers 401. */
export default function Unauthorized() {
  const t = useExtracted("app");
  return (
    <Empty role="alert" className="m-6 border">
      <EmptyHeader>
        <EmptyMedia variant="icon">
          <LogInIcon />
        </EmptyMedia>
        <EmptyTitle>{t("Sign in to continue")}</EmptyTitle>
        <EmptyDescription>{t("Your session has ended.")}</EmptyDescription>
      </EmptyHeader>
      <EmptyContent>
        <Link href="/login" className={buttonVariants()}>
          {t("Sign in")}
        </Link>
      </EmptyContent>
    </Empty>
  );
}
