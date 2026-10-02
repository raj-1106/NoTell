import type { Interface } from "ethers";
import { FRIENDLY_ERROR_MESSAGES, GENERIC_FALLBACK } from "./errorMessages";

export interface FriendlyError {
  title: string;
  message: string;
  /** Real error name/message for logging only. Never render this to the user. */
  debug: string;
}

function extractRevertData(error: any): string | undefined {
  return (
    error?.data ??
    error?.info?.error?.data ??
    error?.error?.data ??
    error?.error?.error?.data ??
    undefined
  );
}

export function decodeError(error: unknown, contractInterface: Interface): FriendlyError {
  const err = error as any;

  if (err?.code === 4001 || err?.code === "ACTION_REJECTED") {
    return { title: "Transaction cancelled", message: "You closed the wallet prompt. Nothing was submitted.", debug: "user_rejected" };
  }

  if (err?.code === "INSUFFICIENT_FUNDS" || /insufficient funds/i.test(err?.message ?? "")) {
    return { title: "Not enough funds", message: "Your wallet doesn't have enough MON to cover this transaction and gas.", debug: "insufficient_funds" };
  }

  const data = extractRevertData(err);
  if (data) {
    try {
      const parsed = contractInterface.parseError(data);
      if (parsed) {
        const friendly = FRIENDLY_ERROR_MESSAGES[parsed.name];
        if (friendly) return { ...friendly, debug: parsed.name };
        return { title: "Transaction reverted", message: `The contract rejected this action (${parsed.name}).`, debug: parsed.name };
      }
    } catch {
      // data didn't match any error in this ABI, fall through to generic handling
    }
  }

  if (/413|payload too large/i.test(err?.message ?? "")) {
    return { title: "Network is busy", message: "The network couldn't process that request. Please try again shortly.", debug: "rpc_413" };
  }

  return { ...GENERIC_FALLBACK, debug: err?.message ?? String(err) };
}
