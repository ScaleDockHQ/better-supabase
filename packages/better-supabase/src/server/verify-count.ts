/** Counts the real token verifications of one resolution, and forwards them. */
export interface VerifyCount {
  readonly onVerify: () => void;
  readonly count: () => number;
}

export const countVerifications = (forward?: () => void): VerifyCount => {
  let verifications = 0;

  return {
    onVerify: () => {
      verifications += 1;
      forward?.();
    },
    count: () => verifications,
  };
};
