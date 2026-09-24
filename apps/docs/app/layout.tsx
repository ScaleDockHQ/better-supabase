import type { Metadata } from 'next';
import type { ReactNode } from 'react';

import { RootProvider } from 'fumadocs-ui/provider/next';

import './global.css';

export const metadata: Metadata = {
  title: {
    default: 'better-supabase',
    template: '%s | better-supabase',
  },
  description:
    'Strongly typed repositories, auth glue, framework adapters and cache helpers for Supabase.',
};

export default function Layout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className="flex min-h-screen flex-col">
        <RootProvider>{children}</RootProvider>
      </body>
    </html>
  );
}
