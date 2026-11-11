import type { ReactNode } from "react";

import { NextIntlClientProvider, useMessages } from "next-intl";

import { AiSubnav } from "@/features/assistant/components/ai-subnav";
import { APP_NAMESPACES, pick } from "@/i18n/namespaces";

export default function AssistantLayout({ children }: { children: ReactNode }) {
  const messages = useMessages();

  return (
    <NextIntlClientProvider
      messages={pick(messages, [
        ...APP_NAMESPACES,
        "aiTasks",
        "agents",
        "aiUsage",
        "assistant",
        "evals",
        "guardrails",
        "opsList",
        "prompts",
        "recordList",
      ])}
    >
      <AiSubnav />
      {children}
    </NextIntlClientProvider>
  );
}
