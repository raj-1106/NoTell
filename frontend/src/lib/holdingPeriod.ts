export interface HoldingStatus {
  isEligible: boolean;
  blocksRemaining: number;
  /** Rough estimate only — real block time varies, never treat as exact. */
  estimatedSecondsRemaining: number;
}

/**
 * Pure calculation, mirrors InsurancePool's on-chain check exactly:
 * eligible once currentBlock >= startBlock + holdingPeriodBlocks (inclusive boundary,
 * confirmed by test_ClaimSucceedsAtExactHoldingPeriod).
 */
export function computeHoldingStatus(
  currentBlock: number,
  startBlock: number,
  holdingPeriodBlocks: number,
  blockTimeMs: number
): HoldingStatus {
  const eligibleAtBlock = startBlock + holdingPeriodBlocks;
  // Clamp negative remaining to 0 rather than showing a negative number if
  // currentBlock is somehow behind startBlock (e.g. a stale read racing a reorg).
  const blocksRemaining = Math.max(0, eligibleAtBlock - currentBlock);
  return {
    isEligible: blocksRemaining <= 0,
    blocksRemaining,
    estimatedSecondsRemaining: Math.round((blocksRemaining * blockTimeMs) / 1000),
  };
}

export function formatDuration(totalSeconds: number): string {
  if (totalSeconds <= 0) return "now";
  const h = Math.floor(totalSeconds / 3600);
  const m = Math.floor((totalSeconds % 3600) / 60);
  if (h > 0) return `~${h}h ${m}m`;
  return `~${m}m`;
}
