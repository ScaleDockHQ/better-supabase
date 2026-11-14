import { ArrowLeftIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { Suspense } from "react";

import { buttonVariants } from "@/components/ui/button";
import {
  FormBuilder,
  FormBuilderSkeleton,
} from "@/features/forms/components/form-builder";
import { PermissionGate } from "@/features/user/components/permission-gate";
import { Link } from "@/i18n/navigation";

/** The back link is the static shell; the form streams in. */
// Next.js validates in development that a navigation here paints without
// waiting on uncached work; tests/instant-routes.spec.ts checks it in a build.
export const instant = true;

export default function FormPage({
  params,
}: PageProps<"/[locale]/forms/[id]">) {
  const t = useExtracted("forms");

  return (
    <>
      <Link
        href="/forms"
        className={buttonVariants({
          variant: "ghost",
          size: "sm",
          className: "w-fit",
        })}
      >
        <ArrowLeftIcon />
        {t("All forms")}
      </Link>
      <Suspense fallback={<FormBuilderSkeleton />}>
        <PermissionGate permission="forms.manage">
          {params.then(({ id }) => (
            <FormBuilder id={id} />
          ))}
        </PermissionGate>
      </Suspense>
    </>
  );
}
