// Vite inlines VITE_* only for literal `import.meta.env.NAME` reads, so these
// keys are declared instead of read through the index signature.
interface ImportMetaEnv {
  readonly VITE_SUPABASE_URL: string;
  readonly VITE_SUPABASE_PUBLISHABLE_KEY: string;
}
