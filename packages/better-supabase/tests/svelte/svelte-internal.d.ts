declare module "svelte/internal/client" {
  export interface Source<T> {
    v: T;
  }
  export function effect_root(fn: () => void): () => void;
  export function render_effect(fn: () => void): void;
  export function flush(): void;
  export function push(props: Record<string, unknown>, runes?: boolean): void;
  export function pop(): void;
  export function state<T>(value: T): Source<T>;
  export function get<T>(source: Source<T>): T;
  export function set<T>(source: Source<T>, value: T): T;
}
