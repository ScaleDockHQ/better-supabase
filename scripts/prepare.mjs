import { execFileSync } from 'node:child_process';
import process from 'node:process';

// Vercel and CI builds have no git hooks to install.
if (!process.env.CI && !process.env.VERCEL) {
  execFileSync('lefthook', ['install'], { stdio: 'inherit' });
}
