// @ts-nocheck
import { describe, it, expect } from "vitest";
import { computeHoldingStatus, formatDuration } from "./holdingPeriod";

describe("computeHoldingStatus", () => {
  it("main case: still waiting, computes correct remaining blocks and estimate", () => {
    const status = computeHoldingStatus(1000, 900, 288000, 300);
    expect(status.isEligible).toBe(false);
    expect(status.blocksRemaining).toBe(287900);
    expect(status.estimatedSecondsRemaining).toBe(287900 * 0.3);
  });

  it("edge case: exactly at the boundary block counts as eligible (matches on-chain >=)", () => {
    const status = computeHoldingStatus(900 + 288000, 900, 288000, 300);
    expect(status.isEligible).toBe(true);
    expect(status.blocksRemaining).toBe(0);
  });

  it("failure case: currentBlock behind startBlock clamps to 0 rather than negative", () => {
    const status = computeHoldingStatus(500, 900, 288000, 300);
    expect(status.blocksRemaining).toBeGreaterThanOrEqual(0);
    expect(status.isEligible).toBe(false);
  });
});

describe("formatDuration", () => {
  it("formats hours and minutes, and shows 'now' at zero", () => {
    expect(formatDuration(0)).toBe("now");
    expect(formatDuration(90)).toBe("~1m");
    expect(formatDuration(3660)).toBe("~1h 1m");
  });
});
