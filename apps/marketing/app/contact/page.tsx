import type { Metadata } from "next";

import { ContactForm } from "@/app/contact/contact-form";
import { LinkButton } from "@/components/site/link-button";
import { site } from "@/lib/site";

export const metadata: Metadata = {
  title: "Contact",
  description: "Get in touch with ScaleDock, the team behind better-supabase.",
};

export default function ContactPage() {
  return (
    <section className="mx-auto grid w-full max-w-5xl grid-cols-1 gap-12 px-6 py-16 md:grid-cols-2 md:px-8">
      <div className="flex flex-col gap-4">
        <h1 className="text-4xl font-semibold text-balance">
          Get in touch with {site.company.name}
        </h1>
        <p className="text-base leading-7 text-muted-foreground">
          better-supabase is built and maintained by {site.company.name}, a team
          that helps companies build and run products on Supabase.
        </p>
        <p className="text-base leading-7 text-muted-foreground">
          Write to us about support, architecture reviews, migrations or
          anything else about the library. We reply by email.
        </p>
        <div className="flex flex-wrap gap-3 pt-2">
          <LinkButton variant="outline" href={site.company.url}>
            About {site.company.name}
          </LinkButton>
          <LinkButton variant="outline" href={`mailto:${site.contactEmail}`}>
            {site.contactEmail}
          </LinkButton>
        </div>
      </div>
      <ContactForm />
    </section>
  );
}
