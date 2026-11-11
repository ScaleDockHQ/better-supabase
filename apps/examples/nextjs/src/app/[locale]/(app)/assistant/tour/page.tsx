import { useExtracted } from "next-intl";

import { PageHeader } from "@/components/page-header";
import { AssistantTourLazy } from "@/features/assistant/components/assistant-tour-lazy";

// The page is static text and one button; the chat mounts after a click.
export const ensureStatic = "shell";
export const instant = true;

export default function AssistantTourPage() {
  const t = useExtracted("assistant");

  return (
    <>
      <PageHeader
        title={t("Assistant tour")}
        description={t(
          "A scripted conversation with no model: reasoning, a tool trace, a cited source, an approval and clarifying questions.",
        )}
      />
      <AssistantTourLazy />
    </>
  );
}
