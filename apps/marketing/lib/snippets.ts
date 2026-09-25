export type Snippet = {
  readonly filename: string;
  readonly language: 'ts' | 'tsx' | 'bash';
  readonly code: string;
};

export const heroSnippet: Snippet = {
  filename: 'app/customers/page.tsx',
  language: 'tsx',
  code: `import { next } from '@/lib/supabase.server';

export default async function Customers() {
  const { db } = await next.server();

  const result = await db.customers.findMany({
    select: ['id', 'name'],
    where: { status: 'active', notes: { some: { kind: 'call' } } },
    include: { organization: { select: ['name'] } },
    orderBy: { name: 'asc' },
    limit: 20,
  });
  // { id: string; name: string; organization: { name: string } }[]

  if (!result.ok) return <ErrorState error={result.error} />;
  return <CustomerList customers={result.data} />;
}`,
};

export const cliSnippet: Snippet = {
  filename: 'terminal',
  language: 'bash',
  code: `pnpm better-supabase init     # config, client and framework glue
pnpm better-supabase gen      # database.types.ts + generated.ts
pnpm better-supabase gen --check  # fail CI on schema drift
pnpm better-supabase doctor   # RLS, indexes and Supabase advisors`,
};
