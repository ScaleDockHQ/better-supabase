import type { Metadata } from "next";

import { PlannedPage } from "@/components/site/planned-page";
import { SiteLink } from "@/components/site/site-link";

export const metadata: Metadata = {
  title: "Create",
  description:
    "Planned: pick blocks and conventions, and get the config, the migrations and one install command.",
};

export default function CreatePage() {
  return (
    <PlannedPage
      eyebrow="Planned"
      title="Create"
      lead="Create will let you pick a preset, your framework and the blocks you need, then show the config file, the migrations and the dependency graph before you install anything."
    >
      <h2>What it will do</h2>
      <p>
        Blocks you depend on switch on with the reason shown, optional
        integrations show as works with, and the selection is kept in the URL so
        you can share it.
      </p>
      <h2>What works today</h2>
      <p>
        Pick blocks on the{" "}
        <SiteLink href="/blocks" className="text-foreground underline">
          blocks page
        </SiteLink>{" "}
        and install them with <code>npx better-supabase sql add</code> followed
        by their names. The command adds the modules each block needs. See{" "}
        <SiteLink href="/docs/blocks/sql" className="text-foreground underline">
          SQL modules
        </SiteLink>{" "}
        for the config and the migration step.
      </p>
    </PlannedPage>
  );
}
