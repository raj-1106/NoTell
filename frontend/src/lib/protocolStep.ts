export type ProtocolStep =
  | "no_policy"
  | "holding_period"
  | "eligible_no_commitment"
  | "commitment_posted"
  | "claimed";

export interface StepInput {
  hasPolicy: boolean;
  isHoldingPeriodElapsed: boolean;
  hasCommitment: boolean; // claimRoundId is non-null
  isClaimed: boolean;
}

/**
 * Pure derivation of "where is this policy in its lifecycle right now."
 * No network calls, no side effects — takes the same booleans the
 * dashboard already computes for HoldingPeriodBadge and the Fetch button.
 */
export function computeProtocolStep(input: StepInput): ProtocolStep {
  if (input.isClaimed) return "claimed";
  if (!input.hasPolicy) return "no_policy";
  if (input.hasCommitment) return "commitment_posted";
  if (input.isHoldingPeriodElapsed) return "eligible_no_commitment";
  return "holding_period";
}

export const STEP_COPY: Record<ProtocolStep, { title: string; description: string }> = {
  no_policy: {
    title: "1. Buy a policy",
    description: "Choose a notional amount and pay the premium to open cover.",
  },
  holding_period: {
    title: "2. Holding period",
    description: "A mandatory waiting period must pass before a claim can be filed, this prevents buying cover and immediately self-liquidating for profit.",
  },
  eligible_no_commitment: {
    title: "3. Waiting for oracle commitment",
    description: "The holding period has passed. Once the position is reported underwater, an on-chain commitment is posted for you to prove a claim against.",
  },
  commitment_posted: {
    title: "4. Generate proof & claim",
    description: "A commitment is available. Generate a zero-knowledge proof in your browser and submit it to claim your payout.",
  },
  claimed: {
    title: "Claim complete",
    description: "Payout has been sent. This policy's lifecycle is finished.",
  },
};
