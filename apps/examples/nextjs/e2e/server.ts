export const port = 3100;

export const baseURL = `http://127.0.0.1:${String(port)}`;

/** The same build with every Supabase request from the server delayed. */
export const latencyPort = 3101;

export const latencyURL = `http://127.0.0.1:${String(latencyPort)}`;

/** The delay on `latencyPort`, in milliseconds. */
export const fetchDelayMs = 3000;
