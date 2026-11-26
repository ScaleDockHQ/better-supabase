import { cacheLife } from "next/cache";
import { cookies } from "next/headers";
import { forbidden, notFound, unauthorized } from "next/navigation";
import { Suspense } from "react";

// Proves that Next.js 16.4 ends the render with the interrupt a function
// throws from inside "use cache: private" (ADR 1252). The page is a fixture,
// not a feature: tests/interrupts.spec.ts opens it and prefetches it.
async function refuse(kind: string): Promise<string> {
  "use cache: private";
  cacheLife({ stale: 30 });
  await cookies();

  if (kind === "not-found") {
    notFound();
  }

  if (kind === "forbidden") {
    forbidden();
  }

  if (kind === "unauthorized") {
    unauthorized();
  }

  return "allowed";
}

async function Probe({ kind }: { kind: string }) {
  return <p data-testid="probe">{await refuse(kind)}</p>;
}

export default function ProbePage({
  params,
}: PageProps<"/[locale]/status/probe/[kind]">) {
  return (
    <Suspense fallback={<p>Loading</p>}>
      {params.then(({ kind }) => (
        <Probe kind={kind} />
      ))}
    </Suspense>
  );
}
