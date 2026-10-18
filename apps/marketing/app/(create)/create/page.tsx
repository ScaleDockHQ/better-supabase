import type { Metadata } from "next";
import type { ReactElement } from "react";

import { Suspense } from "react";

import { Skeleton } from "@/components/ui/skeleton";
import { CreateBuilder } from "@/features/create/components/create-builder";

export const metadata: Metadata = {
  title: "Create",
  description:
    "Pick a preset, your framework, conventions and blocks, see the tables they create, and get the config, the migrations, the wiring and one install command.",
  alternates: { canonical: "/create" },
};

function BuilderSkeleton(): ReactElement {
  return (
    <div aria-busy="true" className="flex w-full flex-1">
      <span className="sr-only">Loading the builder</span>
      <div className="hidden w-80 shrink-0 flex-col gap-4 border-r border-border p-4 lg:flex">
        <div className="grid grid-cols-2 gap-2">
          {["a", "b", "c", "d"].map((key) => (
            <Skeleton key={key} className="h-16 w-full" />
          ))}
        </div>
        {["e", "f", "g"].map((key) => (
          <Skeleton key={key} className="h-8 w-full" />
        ))}
      </div>
      <div className="flex min-h-[calc(100svh-3.5rem)] flex-1 flex-col gap-3 p-4">
        <Skeleton className="h-5 w-48" />
        <Skeleton className="w-full flex-1" />
      </div>
    </div>
  );
}

export default function CreatePage(): ReactElement {
  return (
    <>
      <h1 className="sr-only">Start an app from a preset</h1>
      <Suspense fallback={<BuilderSkeleton />}>
        <CreateBuilder />
      </Suspense>
    </>
  );
}
