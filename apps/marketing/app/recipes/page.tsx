import type { Metadata } from "next";

import { PlannedPage } from "@/components/site/planned-page";
import { SiteLink } from "@/components/site/site-link";

export const metadata: Metadata = {
  title: "Recipes",
  description:
    "Planned: UI recipes that build each block's interface from shadcn components and the block's hooks.",
};

export default function RecipesPage() {
  return (
    <PlannedPage
      eyebrow="Planned"
      title="Recipes"
      lead="better-supabase ships no UI components. A recipe will show how to build one interface, such as a notification bell or a members table, from shadcn components and a block's hooks."
    >
      <h2>What each recipe will show</h2>
      <p>
        The shadcn components to add, the glue to install, and the code for web
        and React Native side by side. The snippets will come from the example
        apps, so they are typechecked and tested.
      </p>
      <h2>What works today</h2>
      <p>
        The blocks with a React entry export hooks you can use with your own
        components; each block page links to its entry and docs. The{" "}
        <SiteLink href="/docs/recipes" className="text-foreground underline">
          app recipes in the docs
        </SiteLink>{" "}
        show which blocks to install for a CRM, project management, a drive,
        scheduling and commerce.
      </p>
    </PlannedPage>
  );
}
