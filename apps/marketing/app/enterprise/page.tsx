import type { Metadata } from 'next';

import { MailIcon, ShieldCheckIcon } from 'lucide-react';

import { Badge } from '@/components/reui/badge';
import { FeatureGrid } from '@/components/sections/feature-grid';
import { Section } from '@/components/sections/section';
import { Button } from '@/components/ui/button';
import { engagements, pillars } from '@/lib/enterprise';
import { site } from '@/lib/site';

export const metadata: Metadata = {
  title: 'Enterprise',
  description:
    'Support, architecture reviews and migrations for teams running better-supabase in production.',
};

export default function EnterprisePage() {
  return (
    <>
      <section className="mx-auto flex w-full max-w-4xl flex-col items-center gap-6 px-6 py-16 text-center">
        <Badge variant="outline" size="xl" radius="full" className="h-7">
          Enterprise
        </Badge>
        <h1 className="max-w-3xl text-4xl font-semibold text-balance sm:text-5xl">
          Run better-supabase in production with confidence
        </h1>
        <p className="text-muted-foreground max-w-xl text-base leading-7">
          The library is MIT licensed. For teams that want a direct line to the
          maintainers, we offer support, reviews and migration help.
        </p>
        <div className="flex flex-wrap justify-center gap-3">
          <Button
            size="lg"
            nativeButton={false}
            render={<a href={`mailto:${site.email}?subject=Enterprise`} />}
          >
            <MailIcon aria-hidden="true" />
            Contact us
          </Button>
          <Button
            variant="outline"
            size="lg"
            nativeButton={false}
            render={<a href={`${site.github}/security`} />}
          >
            <ShieldCheckIcon aria-hidden="true" />
            Security policy
          </Button>
        </div>
      </section>
      <Section
        eyebrow="Posture"
        title="Secure by default, boring on purpose"
        description="The properties security and platform teams ask about first."
      >
        <FeatureGrid items={pillars} columns={3} />
      </Section>
      <Section eyebrow="Work with us" title="How we can help">
        <div className="grid gap-3 md:grid-cols-3">
          {engagements.map((item) => (
            <div
              key={item.title}
              className="border-border bg-card flex flex-col gap-2 rounded-xl border p-5"
            >
              <h3 className="text-sm font-semibold">{item.title}</h3>
              <p className="text-muted-foreground text-sm leading-6">
                {item.body}
              </p>
            </div>
          ))}
        </div>
      </Section>
      <section className="mx-auto w-full max-w-6xl px-6 pb-20 md:px-8">
        <div className="border-border bg-card flex flex-col items-center gap-4 rounded-2xl border px-6 py-12 text-center">
          <h2 className="text-2xl font-semibold tracking-tight">
            Talk to the maintainers
          </h2>
          <p className="text-muted-foreground max-w-md text-sm leading-6">
            Tell us about your stack, your Supabase setup and what you need.
          </p>
          <Button
            variant="outline"
            size="lg"
            nativeButton={false}
            render={<a href={`mailto:${site.email}?subject=Enterprise`} />}
          >
            {site.email}
          </Button>
        </div>
      </section>
    </>
  );
}
