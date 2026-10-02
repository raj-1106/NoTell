import { computeHoldingStatus, formatDuration } from "../lib/holdingPeriod";
import "./HoldingPeriodBadge.css";

interface Props {
  currentBlock: number;
  startBlock: number;
  holdingPeriodBlocks: number;
  /** Guessed at ~300ms per earlier confirmed mainnet figure; verify against
      testnet RPC if this ever needs to be precise rather than approximate. */
  blockTimeMs?: number;
}

export function HoldingPeriodBadge({
  currentBlock,
  startBlock,
  holdingPeriodBlocks,
  blockTimeMs = 309,
}: Props) {
  const status = computeHoldingStatus(currentBlock, startBlock, holdingPeriodBlocks, blockTimeMs);

  if (status.isEligible) {
    return <span className="holding-badge holding-badge--ready">Eligible to claim</span>;
  }

  return (
    <span className="holding-badge holding-badge--waiting">
      Eligible in {formatDuration(status.estimatedSecondsRemaining)}
      <span className="holding-badge__blocks"> ({status.blocksRemaining} blocks)</span>
    </span>
  );
}
