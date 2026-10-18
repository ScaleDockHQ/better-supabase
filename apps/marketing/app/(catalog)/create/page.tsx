import type { Metadata } from "next";

import { Suspense } from "react";

import { Skeleton } from "@/components/ui/skeleton";
import { PageHeader } from "@/features/catalog/components/page-header";
import { CreateBuilder } from "@/features/create/components/create-builder";

export const metadata: Metadata = {
  title: "Create",
  description:
    "Pick a preset, your framework, conventions and blocks, and get the config, the migrations, the wiring and one install command.",
  alternates: { canonical: "/create" },
};

function BuilderSkeleton() {
  return (
    <div aria-busy="true" className="flex flex-col gap-10">
      <span className="sr-only">Loading the builder</span>
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 2xl:grid-cols-4">
        {["a", "b", "c", "d"].map((key) => (
          <Skeleton key={key} className="h-24 w-full" />
        ))}
      </div>
      <div className="grid grid-cols-1 gap-10 xl:grid-cols-2">
        <Skeleton className="h-96 w-full" />
        <Skeleton className="h-96 w-full" />
      </div>
    </div>
  );
}

export default function CreatePage() {
  return (
    <div className="flex flex-col gap-10">
      <PageHeader eyebrow="Create" title="Start an app from a preset">
        <p>
          Pick a preset, then change the framework, the conventions and the
          blocks. Blocks the selection depends on switch on with the reason, and
          the URL keeps the selection as a code you can share or put in your
          config as <code className="font-mono text-code">preset</code>.
        </p>
      </PageHeader>
      <Suspense fallback={<BuilderSkeleton />}>
        <CreateBuilder />
      </Suspense>
    </div>
  );
}
