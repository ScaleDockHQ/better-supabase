import { CodeBlock } from "@/components/code-block";
import { Section } from "@/components/sections/section";
import { Button } from "@/components/ui/button";
import { cliSnippet } from "@/lib/snippets";

const points: readonly string[] = [
  "gen --check fails CI when the database and generated types drift apart.",
  "doctor checks RLS, indexes, auth config and env files, and runs the Supabase Security and Performance Advisors locally.",
  "Reports as text, JSON, SARIF or GitHub annotations.",
];

export function CliSection() {
  return (
    <Section
      id="cli"
      eyebrow="CLI"
      title="Codegen and diagnostics in one command line"
      description="One binary for the whole loop: set up a project, generate types from your local stack, and catch security and performance problems before they ship."
    >
      <div className="grid items-start gap-8 lg:grid-cols-2">
        <CodeBlock snippet={cliSnippet} />
        <div className="flex flex-col gap-4">
          <ul className="flex flex-col gap-3">
            {points.map((point) => (
              <li key={point} className="flex gap-3 text-sm leading-6">
                <span
                  aria-hidden="true"
                  className="bg-brand mt-2 size-1.5 shrink-0 rounded-full"
                />
                <span className="text-muted-foreground">{point}</span>
              </li>
            ))}
          </ul>
          <div>
            <Button
              variant="outline"
              nativeButton={false}
              render={<a href="/docs/cli" />}
            >
              CLI reference
            </Button>
          </div>
        </div>
      </div>
    </Section>
  );
}
