import { InboxIcon } from "lucide-react";
import { useExtracted } from "next-intl";

import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";

// A navigation here keeps the queue and shows this pane at once.
export const instant = true;

export default function InboxPage() {
  const t = useExtracted("inbox");

  return (
    <div data-recipe="inbox-threads" className="flex h-full">
      <Empty>
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <InboxIcon />
          </EmptyMedia>
          <EmptyTitle>{t("Pick a conversation")}</EmptyTitle>
          <EmptyDescription>
            {t("Its messages, notes, context and actions show here.")}
          </EmptyDescription>
        </EmptyHeader>
      </Empty>
    </div>
  );
}
