interface DenoHttpServer {
  readonly finished: Promise<void>;
  shutdown(): Promise<void>;
}

declare const Deno: {
  serve(
    handler: (request: Request) => Response | Promise<Response>,
  ): DenoHttpServer;
};
