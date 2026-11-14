import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  SequenceBuilder,
  SequenceBuilderSkeleton,
} from "@/features/sequences/components/sequence-builder";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { Link } from "@/i18n/navigation";

// A navigation here shows the back link at once; the sequence streams in.
export const instant = true;

export default function SequencePage({
  params,
}: PageProps<"/[locale]/crm/sequences/[id]">) {
  const t = useExtracted("sequences");

  return (
    <>
      <Link
        href="/crm/sequences"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All sequences")}
      </Link>
      <Suspense fallback={<SequenceBuilderSkeleton />}>
        <PermissionGate permission="sequences.read">
          {params.then(({ id }) => (
            <SequenceBuilder id={id} />
          ))}
        </PermissionGate>
      </Suspense>
    </>
  );
}
