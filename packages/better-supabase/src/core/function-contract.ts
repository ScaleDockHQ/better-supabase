/** What a typed Edge Function takes and returns, as the caller sees them. */
export interface FunctionContract<In = unknown, Out = unknown> {
  readonly input: In;
  readonly output: Out;
}
