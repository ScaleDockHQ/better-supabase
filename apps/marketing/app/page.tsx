import { CliSection } from '@/components/sections/cli';
import { Closer } from '@/components/sections/closer';
import { FaqSection } from '@/components/sections/faq';
import { FeatureGrid } from '@/components/sections/feature-grid';
import { GetStarted } from '@/components/sections/get-started';
import { HomeHero } from '@/components/sections/home-hero';
import { RuntimesBand } from '@/components/sections/runtimes-band';
import { Section } from '@/components/sections/section';
import { features, frameworks } from '@/lib/home';

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
      <Section
        id="frameworks"
        eyebrow="Frameworks"
        title="Works where your code runs"
        description="Adapters build a per-request client for the caller, so the same repository API works in pages, routes, procedures and functions."
      >
        <FeatureGrid items={frameworks} columns={3} />
      </Section>
      <CliSection />
      <RuntimesBand />
      <GetStarted />
      <FaqSection />
      <Closer />
    </>
  );
}
