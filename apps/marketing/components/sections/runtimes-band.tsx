import { runtimes } from "@/lib/home";

export function RuntimesBand() {
  return (
    <section className="border-y border-border bg-muted/30">
      <div className="mx-auto flex w-full max-w-6xl flex-col items-center gap-6 px-6 py-12 text-center md:px-8">
        <div className="flex max-w-2xl flex-col gap-2">
          <h2 className="text-xl font-semibold tracking-tight sm:text-2xl">
            Runs on every WinterTC runtime
          </h2>
          <p className="text-sm leading-6 text-muted-foreground">
            Runtime entries import no Node built-ins, and the core has no
            dependencies beyond the Supabase packages and Standard Schema.
          </p>
        </div>
        <ul className="flex flex-wrap justify-center gap-2">
          {runtimes.map((runtime) => (
            <li
              key={runtime}
              className="rounded-full border border-border bg-background px-3 py-1 text-sm"
            >
              {runtime}
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
