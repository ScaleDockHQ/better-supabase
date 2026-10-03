import { LinkButton } from "@/components/site/link-button";
import { site } from "@/lib/site";

export function Closer() {
  return (
    <section className="mx-auto w-full max-w-6xl px-6 pb-20 md:px-8">
      <div className="border-border bg-card flex flex-col items-center gap-6 rounded-2xl border px-6 py-14 text-center">
        <h2 className="max-w-2xl text-2xl font-semibold tracking-tight text-balance sm:text-3xl">
          Stop rewriting the glue code every Supabase app needs
        </h2>
        <p className="text-muted-foreground max-w-xl text-base leading-7">
          Start with one table and one query. Keep supabase-js for everything
          else.
        </p>
        <div className="flex flex-wrap justify-center gap-3">
          <LinkButton size="lg" href={site.getStarted}>
            Read the quickstart
          </LinkButton>
          <LinkButton variant="outline" size="lg" href={site.github}>
            Star on GitHub
          </LinkButton>
        </div>
      </div>
    </section>
  );
}
