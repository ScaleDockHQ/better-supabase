import { CatalogShowcase } from "@/components/sections/catalog-showcase";
import { CliSection } from "@/components/sections/cli";
import { Closer } from "@/components/sections/closer";
import { FaqSection } from "@/components/sections/faq";
import { FeatureGrid } from "@/components/sections/feature-grid";
import { GetStarted } from "@/components/sections/get-started";
import { HomeHero } from "@/components/sections/home-hero";
import { LogoCloud } from "@/components/sections/logo-cloud";
import { RecipesStrip } from "@/components/sections/recipes-strip";
import { Section } from "@/components/sections/section";
import { JsonLd } from "@/components/site/json-ld";
import { faq, features } from "@/lib/home";
import { integrations, integrationsIn } from "@/lib/integrations";
import { site } from "@/lib/site";
import { faqPage, homeGraph } from "@/lib/structured-data";

export default function HomePage() {
  return (
    <>
      <HomeHero />
      <Section
        id="features"
        eyebrow="What you get"
        title="The glue code every Supabase app rewrites, done once"
        description="Auth wiring, typed repositories, pagination, includes, nested filters, soft delete, timestamps, upserts, cache invalidation, list pages, storage paths and realtime topics."
      >
        <FeatureGrid items={features} />
      </Section>
      <CatalogShowcase />
      <RecipesStrip />
      <LogoCloud />
      <CliSection />
      <GetStarted />
      <FaqSection />
      <Closer />
      <JsonLd
        data={homeGraph({
          name: site.name,
          url: site.url,
          description: site.tagline,
          github: site.github,
          npm: site.npm,
          company: site.company,
          runtimes: integrationsIn("Runtimes").map(
            (integration) => integration.name,
          ),
          frameworks: integrations
            .filter((integration) => integration.group !== "Runtimes")
            .map((integration) => integration.name),
        })}
      />
      <JsonLd data={faqPage(faq)} />
    </>
  );
}
