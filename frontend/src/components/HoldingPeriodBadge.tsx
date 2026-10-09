import { computeHoldingStatus, formatDuration } from "../lib/holdingPeriod";
import "./HoldingPeriodBadge.css";

interface Props {
  currentBlock: number;
  startBlock: number;
  holdingPeriodBlocks: number;
  /** Approximate Monad block time in milliseconds. Defaults to 309ms (measured). */
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
