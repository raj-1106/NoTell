import { indexer } from "envio";
import type { Policy, PoolSnapshot, ClaimEvent } from "envio";

const GLOBAL_POOL_ID = "1";

const getPoolSnapshot = async (context: any): Promise<PoolSnapshot> => {
  let pool = await context.PoolSnapshot.get(GLOBAL_POOL_ID);
  if (!pool) {
    pool = {
      id: GLOBAL_POOL_ID,
      totalAssets: 0n,
      totalPremiums: 0n,
      totalClaimsPaid: 0n,
      activePolicies: 0n,
    };
  }
  return pool;
};



indexer.onEvent(
  { contract: "PolicyRegistry", event: "PolicyIssued" },
  async ({ event, context }) => {
    const policy: Policy = {
      id: event.params.policyId.toString(),
      holder: event.params.holder,
      notional: event.params.notional,
      endBlock: event.params.endBlock,
      state: "Active",
      amountPaid: undefined,
      claimRoundId: undefined,
    };
    context.Policy.set(policy);

    const pool = await getPoolSnapshot(context);
    context.PoolSnapshot.set({
      ...pool,
      activePolicies: pool.activePolicies + 1n,
    });
  }
);

indexer.onEvent(
  { contract: "PolicyRegistry", event: "ClaimWindowOpened" },
  async ({ event, context }) => {
    const policy = await context.Policy.get(event.params.policyId.toString());
    if (policy) {
      context.Policy.set({ 
        ...policy, 
        state: "ClaimWindowOpened",
        claimRoundId: BigInt(event.block.number)
      });
    }
  }
);

indexer.onEvent(
  { contract: "PolicyRegistry", event: "PolicyClaimed" },
  async ({ event, context }) => {
    const policy = await context.Policy.get(event.params.policyId.toString());
    if (policy) {
      context.Policy.set({
        ...policy,
        state: "Claimed",
        amountPaid: event.params.amountPaid,
      });
    }

    const pool = await getPoolSnapshot(context);
    context.PoolSnapshot.set({
      ...pool,
      activePolicies: pool.activePolicies - 1n,
    });
  }
);

indexer.onEvent(
  { contract: "PolicyRegistry", event: "PolicyExpired" },
  async ({ event, context }) => {
    const policy = await context.Policy.get(event.params.policyId.toString());
    if (policy) {
      context.Policy.set({ ...policy, state: "Expired" });
    }

    const pool = await getPoolSnapshot(context);
    context.PoolSnapshot.set({
      ...pool,
      activePolicies: pool.activePolicies - 1n,
    });
  }
);



indexer.onEvent(
  { contract: "InsurancePool", event: "LPDeposit" },
  async ({ event, context }) => {
    const pool = await getPoolSnapshot(context);
    context.PoolSnapshot.set({
      ...pool,
      totalAssets: pool.totalAssets + event.params.assets,
    });
  }
);

indexer.onEvent(
  { contract: "InsurancePool", event: "LPWithdraw" },
  async ({ event, context }) => {
    const pool = await getPoolSnapshot(context);
    context.PoolSnapshot.set({
      ...pool,
      totalAssets: pool.totalAssets - event.params.assets,
    });
  }
);

indexer.onEvent(
  { contract: "InsurancePool", event: "PremiumCollected" },
  async ({ event, context }) => {
    const pool = await getPoolSnapshot(context);
    context.PoolSnapshot.set({
      ...pool,
      totalAssets: pool.totalAssets + event.params.amount,
      totalPremiums: pool.totalPremiums + event.params.amount,
    });
  }
);

indexer.onEvent(
  { contract: "InsurancePool", event: "ClaimPaid" },
  async ({ event, context }) => {
    const pool = await getPoolSnapshot(context);
    context.PoolSnapshot.set({
      ...pool,
      totalAssets: pool.totalAssets - event.params.amount,
      totalClaimsPaid: pool.totalClaimsPaid + event.params.amount,
    });

    const claimEvent: ClaimEvent = {
      id: `${event.transaction.hash}-${event.logIndex}`,
      policyId: event.params.policyId,
      recipient: event.params.recipient,
      amount: event.params.amount,
      timestamp: BigInt(event.block.timestamp),
    };
    context.ClaimEvent.set(claimEvent);
  }
);
