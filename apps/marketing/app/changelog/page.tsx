import type { Metadata } from "next";

import { ChangelogReleases } from "@/components/sections/changelog-releases";

export const metadata: Metadata = {
  title: "Changelog",
  description:
    "Every better-supabase release, built from the package changelog.",
};

export default function ChangelogPage() {
  return (
    <div className="mx-auto w-full max-w-3xl px-6 py-16 md:px-8">
      <div className="mb-10 flex flex-col gap-2">
        <h1 className="text-3xl font-semibold tracking-tight">Changelog</h1>
        <p className="text-muted-foreground text-base leading-7">
          Built at compile time from the better-supabase CHANGELOG.md, which
          changesets writes on every release.
        </p>
      </div>
      <ChangelogReleases />
    </div>
  );
}
