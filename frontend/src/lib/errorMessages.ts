export const FRIENDLY_ERROR_MESSAGES: Record<string, { title: string; message: string }> = {
  PositionAlreadyLiquidatable: {
    title: "Already in shortfall",
    message: "This position is already eligible for liquidation. Cover can only be bought for healthy positions.",
  },
  HoldingPeriodNotElapsed: {
    title: "Too early to claim",
    message: "This policy hasn't reached its minimum holding period yet. Check back once 24 hours have passed since purchase.",
  },
  ZeroCommitment: {
    title: "No matching commitment found",
    message: "We couldn't find an oracle commitment for this proof yet. The monitor may not have checked this position, try again in a minute.",
  },
  InvalidCommitment: {
    title: "Commitment mismatch",
    message: "The commitment doesn't match the oracle's recorded data for this round.",
  },
  StaleProof: {
    title: "Proof has expired",
    message: "This proof was generated against an outdated commitment. Refresh the position and generate a new proof.",
  },
  ProofFailed: {
    title: "Zero-Knowledge Proof Failed",
    message: "The generated proof is mathematically invalid. This usually means the claimed shortfall doesn't match the oracle's data.",
  },
  InsufficientPoolLiquidity: {
    title: "Pool can't cover this claim right now",
    message: "The insurance pool doesn't currently have enough reserved liquidity to pay this in full. Please try again shortly.",
  },
  PolicyNotClaimable: {
    title: "Policy not claimable",
    message: "This policy is either expired, already claimed, or not active.",
  },
  NotPolicyHolder: {
    title: "Unauthorized",
    message: "You can only claim payouts for policies you own.",
  }
};

export const GENERIC_FALLBACK = {
  title: "Something went wrong",
  message: "We couldn't complete this action. Please try again.",
};
