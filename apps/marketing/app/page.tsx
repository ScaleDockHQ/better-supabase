import { AdoptLadder } from "@/components/sections/adopt-ladder";
import { AgentsSection } from "@/components/sections/agents";
import { BeforeAfter } from "@/components/sections/before-after";
import { CatalogShowcase } from "@/components/sections/catalog-showcase";
import { Closer } from "@/components/sections/closer";
import { FaqSection } from "@/components/sections/faq";
import { FeatureGrid } from "@/components/sections/feature-grid";
import { GetStarted } from "@/components/sections/get-started";
import { HomeHero } from "@/components/sections/home-hero";
import { HowItWorks } from "@/components/sections/how-it-works";
import { LogoCloud } from "@/components/sections/logo-cloud";
import { PresetGallery } from "@/components/sections/preset-gallery";
import { ProofStrip } from "@/components/sections/proof-strip";
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
      <ProofStrip />
      <HowItWorks />
      <PresetGallery />
      <CatalogShowcase />
      <AdoptLadder />
      <BeforeAfter />
      <RecipesStrip />
      <Section
        id="features"
        eyebrow="The typed layer"
        title="The glue code every Supabase app rewrites, done once"
        description="Under the blocks sits the library: generated types, a typed repository, auth wiring, cache invalidation and adapters for your framework."
      >
        <FeatureGrid items={features} />
      </Section>
      <AgentsSection />
      <LogoCloud />
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
