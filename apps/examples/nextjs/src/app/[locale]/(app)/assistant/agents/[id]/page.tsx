import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  AgentDetail,
  AgentDetailSkeleton,
} from "@/features/agents/components/agent-detail";
import { Link } from "@/i18n/navigation";

// The back link and the skeleton paint at once; the agent streams in.
export const instant = true;

export default function AgentPage({
  params,
}: PageProps<"/[locale]/assistant/agents/[id]">) {
  const t = useExtracted("agents");

  return (
    <>
      <Link
        href="/assistant/agents"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All agents")}
      </Link>
      <Suspense fallback={<AgentDetailSkeleton />}>
        {params.then(({ id }) => (
          <AgentDetail id={id} />
        ))}
      </Suspense>
    </>
  );
}
