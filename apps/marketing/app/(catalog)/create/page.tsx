import type { Metadata } from "next";

import { Suspense } from "react";

import { CreateBuilder } from "@/components/create/create-builder";

export const metadata: Metadata = {
  title: "Create",
  description:
    "Pick a preset, your framework, conventions and blocks, and get the config, the migrations, the wiring and one install command.",
};

export default function CreatePage() {
  return (
    <div className="mx-auto flex w-full max-w-6xl flex-col gap-10 px-6 py-16 md:px-8">
      <div className="flex max-w-2xl flex-col gap-3">
        <p className="text-xs font-semibold tracking-wide text-brand uppercase">
          Create
        </p>
        <h1 className="text-3xl font-semibold tracking-tight">
          Start an app from a preset
        </h1>
        <p className="text-base leading-7 text-pretty text-muted-foreground">
          Pick a preset, then change the framework, the conventions and the
          blocks. Blocks the selection depends on switch on with the reason, and
          the URL keeps the selection as a code you can share or put in your
          config as <code className="font-mono text-code">preset</code>.
        </p>
      </div>
      <Suspense
        fallback={
          <p className="text-sm text-muted-foreground">Loading the builder.</p>
        }
      >
        <CreateBuilder />
      </Suspense>
    </div>
  );
}
