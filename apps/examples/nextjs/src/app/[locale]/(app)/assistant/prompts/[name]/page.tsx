import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  PromptDetail,
  PromptDetailSkeleton,
} from "@/features/prompts/components/prompt-detail";
import { Link } from "@/i18n/navigation";

export const instant = true;

export default function PromptPage({
  params,
}: PageProps<"/[locale]/assistant/prompts/[name]">) {
  const t = useExtracted("prompts");

  return (
    <>
      <Link
        href="/assistant/prompts"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All prompts")}
      </Link>
      <Suspense fallback={<PromptDetailSkeleton />}>
        {params.then(({ name }) => (
          <PromptDetail name={decodeURIComponent(name)} />
        ))}
      </Suspense>
    </>
  );
}
