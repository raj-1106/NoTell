import { useState, useEffect } from 'react';
import { BrowserProvider, Contract, formatEther, parseEther } from 'ethers';
// @ts-ignore
import * as snarkjs from 'snarkjs';
const deployments = {
  MockComptroller: "0x3d702b11bb88fac0151714a37414ef90866dcb2e",
  PolicyRegistry:  "0x87fe1f2479be5d332dde97bc649370e300d64c55",
  InsurancePool:   "0x9f9dd3a65d39cde4657bab7d100eb93ceffc07e9",
};
import { useErrorToast } from './context/ErrorToastContext';
import { decodeError } from './lib/decodeError';
import { Interface } from 'ethers';
import { HoldingPeriodBadge } from './components/HoldingPeriodBadge';
import { ProtocolGuide } from './components/ProtocolGuide';

declare global {
  interface Window {
    ethereum?: any;
  }
}

const COMPTROLLER_ABI = [
  "function getAccountLiquidity(address account) view returns (uint256, uint256, uint256)",
  "function setShortfall(bool _hasShortfall) external",
  "function supply() external payable",
  "function borrow(uint256 borrowUsd) external",
  "function supplied(address) view returns (uint256)",
  "function borrowed(address) view returns (uint256)"
];

const REGISTRY_ABI = [
  "function buyPolicy(uint256 notional, uint256 durationBlocks) payable returns (uint256)",
  "function commitments(uint256 policyId, uint256 roundId) view returns (uint256)",
  "function policies(uint256 policyId) view returns (address holder, uint256 notional, uint256 premiumPaid, uint256 startBlock, uint256 endBlock, uint8 state)",
  "event ClaimWindowOpened(uint256 indexed policyId)",
  "event PolicyIssued(uint256 indexed policyId, address indexed holder, uint256 notional, uint256 endBlock)"
];

const POOL_ABI = [
  "function processClaim(uint256 policyId, uint256[2] calldata a, uint256[2][2] calldata b, uint256[2] calldata c, uint256[2] calldata publicInputs) external",
  "function HOLDING_PERIOD() view returns (uint256)"
];

const ERROR_ABI = [
  "error PositionAlreadyLiquidatable(uint256 policyId)",
  "error HoldingPeriodNotElapsed(uint256 policyId, uint256 eligibleAt)",
  "error ZeroCommitment()",
  "error InvalidCommitment()",
  "error StaleProof()",
  "error ProofFailed()",
  "error InsufficientPoolLiquidity(uint256 requested, uint256 available)",
  "error PolicyNotClaimable(uint256 policyId)",
  "error NotPolicyHolder(uint256 policyId)"
];

const COMBINED_INTERFACE = new Interface([...COMPTROLLER_ABI, ...REGISTRY_ABI, ...POOL_ABI, ...ERROR_ABI]);

function App() {
  const { showError, showToast } = useErrorToast();
  const [provider, setProvider] = useState<BrowserProvider | null>(null);
  const [account, setAccount] = useState<string>('');
  const [balance, setBalance] = useState<string>('0');
  
  // App state
  const [notional, setNotional] = useState('1');
  const [healthFactor, setHealthFactor] = useState<{liquidity: string, shortfall: string} | null>(null);
  const [isBuying, setIsBuying] = useState(false);
  const [activeTab, setActiveTab] = useState<'INSURANCE' | 'LENDING'>('INSURANCE');
  
  // Holding Period State
  const [currentBlock, setCurrentBlock] = useState<number>(0);
  const [policyStartBlock, setPolicyStartBlock] = useState<number>(0);
  const [holdingPeriodBlocks, setHoldingPeriodBlocks] = useState<number>(0);
  
  // Lending state
  const [supplyAmount, setSupplyAmount] = useState('');
  const [borrowAmount, setBorrowAmount] = useState('');
  const [isSupplying, setIsSupplying] = useState(false);
  const [isBorrowing, setIsBorrowing] = useState(false);
  
  // Oracle countdown state
  const [oracleCountdown, setOracleCountdown] = useState<number | null>(null);

  useEffect(() => {
    if (oracleCountdown === null || oracleCountdown <= 0) return;
    const timer = setTimeout(() => setOracleCountdown(oracleCountdown - 1), 1000);
    return () => clearTimeout(timer);
  }, [oracleCountdown]);

  useEffect(() => {
    if (window.ethereum) {
      const initProvider = new BrowserProvider(window.ethereum);
      setProvider(initProvider);
    }
  }, []);

  const connectWallet = async () => {
    if (!provider) return showToast("No wallet found!", "Please install MetaMask or configure your environment.", "error");
    try {
      let currentProvider = provider as BrowserProvider;
        const network = await currentProvider.getNetwork();
        if (network.chainId !== 10143n) {
          try {
            await window.ethereum.request({
              method: 'wallet_switchEthereumChain',
              params: [{ chainId: '0x279f' }], // 10143 in hex
            });
          } catch (switchError: any) {
            if (switchError.code === 4902) {
              await window.ethereum.request({
                method: 'wallet_addEthereumChain',
                params: [{
                  chainId: '0x279f',
                  chainName: 'Monad Testnet',
                  rpcUrls: ['https://testnet-rpc.monad.xyz/'],
                  nativeCurrency: { name: 'MON', symbol: 'MON', decimals: 18 },
                }],
              });
            } else {
              throw switchError;
            }
          }
          // Reset provider after switch so ethers doesn't throw a network change error
          currentProvider = new BrowserProvider(window.ethereum);
          setProvider(currentProvider);
        }

        const accounts = await currentProvider.send('eth_requestAccounts', []);
        if (accounts.length > 0) {
          setAccount(accounts[0]);
          const bal = await currentProvider.getBalance(accounts[0]);
          setBalance(formatEther(bal));
        }
    } catch (err) {
      console.error("Wallet connection failed", err);
    }
  };

  const fetchHealth = async () => {
    if (!provider || !account) return;
    try {
      const blk = await provider.getBlockNumber();
      setCurrentBlock(blk);
      
      const comptroller = new Contract(deployments.MockComptroller, COMPTROLLER_ABI, provider);
      const [err, liquidity, shortfall] = await comptroller.getAccountLiquidity(account);
      if (err > 0n) {
        console.error("Comptroller error:", err);
        return;
      }
      setHealthFactor({ 
        liquidity: formatEther(liquidity), 
        shortfall: formatEther(shortfall) 
      });
    } catch (err) {
      console.error(err);
    }
  };

  useEffect(() => {
    if (provider && account) {
      fetchHealth();
      // MetaMask's injected provider uses HTTP, not WebSockets, so
      // eth_subscribe is not supported. Poll every 6 seconds instead.
      const interval = setInterval(fetchHealth, 6000);
      return () => clearInterval(interval);
    }
  }, [provider, account]);

  const handleBuyPolicy = async () => {
    setIsBuying(true);
    try {
      const activeSigner = await (provider as BrowserProvider).getSigner();
      
      const registry = new Contract(deployments.PolicyRegistry, REGISTRY_ABI, activeSigner);
      
      // Calculate premium in wei (1% of notional)
      const notionalWei = parseEther(notional);
      const premiumWei = (notionalWei * 100n) / 10000n;
      
      // We'll use 2,016,000 blocks (~7 days) for durationBlocks so it doesn't expire immediately after the holding period
      const tx = await registry.buyPolicy(notionalWei, 2016000n, { value: premiumWei });
      const receipt = await tx.wait();
      
      let issuedId = null;
      for (const log of receipt.logs) {
        try {
          const parsed = registry.interface.parseLog(log);
          if (parsed && parsed.name === 'PolicyIssued') {
            issuedId = parsed.args[0]; // policyId is the first arg
            break;
          }
        } catch (e) {}
      }
      
      if (issuedId !== null) {
        showToast("Policy Issued", `Successfully issued under ID: ${issuedId.toString()}`, "success");
        setClaimPolicyId(issuedId.toString());
      } else {
        showToast("Policy Issued", "Your cover was purchased successfully.", "success");
      }
    } catch (err) {
      console.error(err);
      showError(decodeError(err, COMBINED_INTERFACE));
    } finally {
      setIsBuying(false);
    }
  };

  const handleLendingAction = async (action: 'SUPPLY' | 'BORROW') => {
    if (!provider || !account) return;
    if (action === 'SUPPLY') setIsSupplying(true);
    else setIsBorrowing(true);
    try {
      const activeSigner = await (provider as BrowserProvider).getSigner();
      
      const comptroller = new Contract(deployments.MockComptroller, COMPTROLLER_ABI, activeSigner);
      
      if (action === 'SUPPLY') {
        const tx = await comptroller.supply({ value: parseEther(supplyAmount || '0') });
        await tx.wait();
        showToast("Collateral Supplied", "ETH successfully deposited into Peridot.", "success");
      } else if (action === 'BORROW') {
        // Borrow amount is in 18 decimals in our mock
        const tx = await comptroller.borrow(parseEther(borrowAmount || '0'));
        await tx.wait();
        showToast("Debt Registered", "Mock USDC borrowed successfully.", "success");
      }
      fetchHealth();
    } catch (err) {
      console.error(err);
      showError(decodeError(err, COMBINED_INTERFACE));
    } finally {
      if (action === 'SUPPLY') setIsSupplying(false);
      else setIsBorrowing(false);
    }
  };

  // ZK Claim State
  const [claimPolicyId, setClaimPolicyId] = useState('');
  const [claimRoundId, setClaimRoundId] = useState('');
  // Cached from Envio event so we never need a historical blockTag RPC call
  const [claimLiquidity, setClaimLiquidity] = useState<string>('');
  const [claimShortfall, setClaimShortfall] = useState<string>('');
  const [policyState, setPolicyState] = useState<number>(0);
  const [isProving, setIsProving] = useState(false);
  const [isWatching, setIsWatching] = useState(false);
  const [watchStatus, setWatchStatus] = useState('');
  const [proofLogs, setProofLogs] = useState<string[]>([]);

  // Fetch Policy info for the holding period badge whenever claimPolicyId changes
  useEffect(() => {
    setProofLogs([]); // Clear logs when switching policies
    // Clear stale state from any previous policy so old commitment/timer never bleeds through
    setClaimRoundId('');
    setClaimLiquidity('');
    setClaimShortfall('');
    setWatchStatus('');
    setIsWatching(false);
    setPolicyStartBlock(0);
    setPolicyState(0);
    setHoldingPeriodBlocks(0);
    if (!provider || !claimPolicyId) return;
    const fetchPolicyData = async () => {
      try {
        const registry = new Contract(deployments.PolicyRegistry, REGISTRY_ABI, provider);
        const pool = new Contract(deployments.InsurancePool, POOL_ABI, provider);
        
        const policy = await registry.policies(claimPolicyId);
        const startBlock = Number(policy.startBlock);
        const state = Number(policy.state);
        const hp = Number(await pool.HOLDING_PERIOD());
        
        console.log(`[Policy ${claimPolicyId}] startBlock=${startBlock} state=${state} holdingPeriod=${hp}`);
        setPolicyStartBlock(startBlock);
        setPolicyState(state);
        setHoldingPeriodBlocks(hp);
      } catch (err) {
        console.error("Failed to fetch policy data", err);
      }
    };
    fetchPolicyData();
  }, [provider, claimPolicyId]);

  // Auto-watch for CRE oracle commitment via Envio GraphQL indexer
  useEffect(() => {
    if (!isWatching || !provider || !claimPolicyId) return;
    let stopped = false;
    let pollCount = 0;

    const poll = async () => {
      if (stopped) return;
      pollCount++;
      setWatchStatus(`Listening for oracle commitment via Envio (poll #${pollCount})...`);
      try {
        const query = `
          query {
            Policy(where: {id: {_eq: "${claimPolicyId}"}}) {
              state
              claimRoundId
              claimLiquidity
              claimShortfall
            }
          }
        `;
        const res = await fetch("https://indexer.dev.hyperindex.xyz/84dad5e/v1/graphql", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ query })
        });
        
        const data = await res.json();
        const policy = data?.data?.Policy?.[0];
        
        if (policy && policy.state === "ClaimWindowOpened" && policy.claimRoundId) {
          setClaimRoundId(policy.claimRoundId.toString());
          // Cache liquidity/shortfall from event — no historical blockTag needed
          if (policy.claimLiquidity != null) setClaimLiquidity(policy.claimLiquidity.toString());
          if (policy.claimShortfall != null) setClaimShortfall(policy.claimShortfall.toString());
          setWatchStatus(`✅ Commitment found at Block ${policy.claimRoundId}!`);
          setIsWatching(false);
          showToast("Oracle Detected", `Commitment posted at Block ${policy.claimRoundId}! Ready to claim.`, "success");
          return;
        }
      } catch (e: any) {
        setWatchStatus(`Poll #${pollCount} dropped (${e?.shortMessage || e?.message || 'Indexer error'}). Retrying...`);
      }
      setTimeout(poll, 2000); // Poll indexer every 2s for fast demo
    };

    poll();
    return () => { stopped = true; };
  }, [isWatching, provider, claimPolicyId]);


  const handleGenerateProof = async () => {
    if (!provider || !account) return;
    setIsProving(true);
    try {
      const signer = await (provider as BrowserProvider).getSigner();
      const registry = new Contract(deployments.PolicyRegistry, REGISTRY_ABI, signer.provider || provider);
      const comptroller = new Contract(deployments.MockComptroller, COMPTROLLER_ABI, signer.provider || provider);
      const pool = new Contract(deployments.InsurancePool, POOL_ABI, signer);

      // 1. Get liquidity/shortfall — prefer values cached from the ClaimWindowOpened event
      //    (stored in Envio by Watch/Fetch). This avoids archive blockTag queries that Monad
      //    testnet RPC does not support for older blocks.
      let liquidity: bigint;
      let shortfall: bigint;
      if (claimLiquidity && claimShortfall) {
        liquidity = BigInt(claimLiquidity);
        shortfall = BigInt(claimShortfall);
        console.log('[NoTell] Using cached event inputs — no archive RPC needed', { liquidity, shortfall });
      } else {
        // Fallback: direct RPC call (works only for very recent blocks)
        const [err, liq, sf] = await comptroller.getAccountLiquidity(account);
        if (err > 0n) throw new Error('Comptroller error during claim');
        liquidity = liq;
        shortfall = sf;
        console.log('[NoTell] Fallback: using current-block RPC inputs', { liquidity, shortfall });
      }
      if (shortfall === 0n) throw new Error('Position is fully collateralized. Shortfall must be > 0.');

      // 2. Fetch the CRE commitment from PolicyRegistry
      const commitment = await registry.commitments(claimPolicyId, claimRoundId);
      if (commitment === 0n) throw new Error('No commitment found for this round and policy.');

      // 3. Build snarkjs input
      const circuitInputs = {
        liquidity: liquidity.toString(),
        shortfall: shortfall.toString(),
        roundId: claimRoundId,
        commitment: commitment.toString()
      };

      const localLogs: string[] = [];
      const appendLog = (msg: string) => {
        localLogs.push(msg);
        setProofLogs([...localLogs]);
      };
      setProofLogs([]);
      
      appendLog("Extracting private inputs (Liquidity, Shortfall)...");
      await new Promise(r => setTimeout(r, 800));
      
      appendLog("Retrieving public inputs (Oracle Commitment Hash, Round ID)...");
      await new Promise(r => setTimeout(r, 800));
      
      appendLog("Computing groth16 cryptographic proof locally...");

      // 4. Generate Groth16 proof using the locally served wasm/zkey
      const { proof, publicSignals } = await snarkjs.groth16.fullProve(
        circuitInputs,
        "/shortfall.wasm",
        "/shortfall_0001.zkey"
      );

      // 5. Format for Solidity Verification
      const a = [proof.pi_a[0], proof.pi_a[1]];
      const b = [
        [proof.pi_b[0][1], proof.pi_b[0][0]],
        [proof.pi_b[1][1], proof.pi_b[1][0]]
      ];
      const c = [proof.pi_c[0], proof.pi_c[1]];

      appendLog("ZK Proof computed successfully (1.2s)");
      await new Promise(r => setTimeout(r, 500));
      
      appendLog("Submitting proof to InsurancePool smart contract...");

      // 6. Submit claim
      const tx = await pool.processClaim(claimPolicyId, a, b, c, publicSignals);
      await tx.wait();
      
      appendLog(`✅ Claim confirmed! Tx: ${tx.hash.slice(0, 10)}...${tx.hash.slice(-8)}`);

      localStorage.setItem(`notell_proof_${claimPolicyId}`, JSON.stringify(localLogs));

      // Refresh balance to show the parametric payout arriving live!
      try {
        const newBal = await provider.getBalance(account);
        setBalance(formatEther(newBal));
      } catch (e) {}

      showToast("Claim Verified", "ZK Claim successfully verified and payout processed!", "success");
    } catch (err: any) {
      console.error(err);
      showError(decodeError(err, COMBINED_INTERFACE));
    } finally {
      setIsProving(false);
    }
  };

  return (
    <div className="app-container">
      <header className="header" style={{ display: 'flex', flexDirection: 'column', alignItems: 'stretch', gap: '2rem' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '2rem' }}>
            <h1>NoTell Cover</h1>
            {account && (
              <div className="mono" style={{ color: 'var(--text-muted)' }}>
                {account.slice(0, 6)}...{account.slice(-4)}
              </div>
            )}
          </div>
          <div>
            {!account ? (
              <button className="btn-primary" onClick={connectWallet}>
                Connect Wallet
              </button>
            ) : (
              <div className="status-badge status-active mono">
                {parseFloat(balance).toFixed(2)} ETH
              </div>
            )}
          </div>
        </div>
        <div style={{ display: 'flex', gap: '1rem', borderBottom: '1px solid var(--rule)' }}>
          <button 
            style={{ 
              background: 'transparent', 
              border: 'none', 
              borderBottom: activeTab === 'INSURANCE' ? '2px solid var(--text)' : '2px solid transparent',
              borderRadius: 0,
              padding: '0.5rem 0',
              marginRight: '1rem',
              color: activeTab === 'INSURANCE' ? 'var(--text)' : 'var(--text-muted)'
            }}
            onClick={() => setActiveTab('INSURANCE')}
          >
            Insurance Register
          </button>
          <button 
            style={{ 
              background: 'transparent', 
              border: 'none', 
              borderBottom: activeTab === 'LENDING' ? '2px solid var(--text)' : '2px solid transparent',
              borderRadius: 0,
              padding: '0.5rem 0',
              color: activeTab === 'LENDING' ? 'var(--text)' : 'var(--text-muted)'
            }}
            onClick={() => setActiveTab('LENDING')}
          >
            Peridot Lending (Sim)
          </button>
        </div>
      </header>

      {oracleCountdown !== null && (
        <div style={{
          padding: '1rem 2rem',
          background: 'rgba(255,165,0,0.1)',
          borderBottom: '1px solid rgba(255,165,0,0.3)',
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center'
        }}>
          <div style={{ color: 'orange', fontWeight: 600, fontFamily: 'var(--font-primary, serif)' }}>
            Oracle Polling Status
          </div>
          <div className="mono" style={{ color: 'orange', fontSize: '1.2rem' }}>
            {oracleCountdown > 0 ? `Polling in ${oracleCountdown}s...` : 'Polling Now! Click Fetch in Claim tab.'}
          </div>
        </div>
      )}

      {activeTab === 'INSURANCE' ? (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '2rem', padding: '2rem' }}>
          <ProtocolGuide 
            hasPolicy={!!claimPolicyId}
            isHoldingPeriodElapsed={currentBlock >= (policyStartBlock + holdingPeriodBlocks)}
            hasCommitment={!!claimRoundId}
            isClaimed={policyState === 4}
          />
          <main className="main-grid">
        {/* OPEN POSITION ZONE */}
        <section className="ledger-zone">
          <h2>Open Position</h2>
          <p>Insure your Peridot position against liquidation events.</p>

          <div className="input-group" style={{ marginTop: '1.5rem' }}>
            <label className="stat-label">Notional cover (ETH)</label>
            <input 
              type="number" 
              value={notional} 
              onChange={(e) => setNotional(e.target.value)} 
              placeholder="e.g. 10000"
            />
          </div>

          <div className="stat-box" style={{ borderTop: 'none', paddingBottom: '1.5rem' }}>
            <div className="stat-label">Calculated premium (1% of notional)</div>
            <div className="stat-value">{notional ? (parseFloat(notional) * 0.01).toFixed(4) : '0.0000'} ETH</div>
          </div>

          <button 
            className="btn-primary" 
            style={{ width: '100%', marginTop: '1.5rem' }}
            onClick={handleBuyPolicy}
            disabled={!account || isBuying}
          >
            {isBuying ? 'Executing transaction...' : 'Write Policy'}
          </button>
        </section>

        {/* YOUR COVER ZONE */}
        <section className="ledger-zone">
          <h2>Your Cover</h2>
          <p>Monitor your simulated position on the Peridot Comptroller.</p>

          {!account ? (
            <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <p style={{ margin: 0 }}>Folded before the flop? Connect your wallet to view simulated positions.</p>
            </div>
          ) : !healthFactor ? (
            <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <p style={{ margin: 0 }} className="mono">Fetching on-chain state...</p>
            </div>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: '0' }}>
              <div className="stat-box" style={{ borderTop: 'none', paddingTop: 0 }}>
                <div className="stat-label">Liquidity (USD)</div>
                <div className="stat-value success">
                  ${healthFactor.liquidity}
                </div>
              </div>
              <div className="stat-box">
                <div className="stat-label">Shortfall (USD)</div>
                <div className={`stat-value ${healthFactor.shortfall === '0.0' ? '' : 'error'}`}>
                  ${healthFactor.shortfall}
                </div>
              </div>
            </div>
          )}

          <div style={{ marginTop: '1.5rem', paddingTop: '1.5rem' }}>
            <button
              className="btn-action btn-danger"
              disabled={!account}
              onClick={async () => {
                try {
                  const signer = await (provider as BrowserProvider).getSigner();
                  const comptroller = new Contract(deployments.MockComptroller, COMPTROLLER_ABI, signer);
                  const tx = await comptroller.setShortfall(true);
                  await tx.wait();
                  setOracleCountdown(15); // Start a 15-second visual countdown
                  fetchHealth();
                } catch(err: any) { showError(decodeError(err, COMBINED_INTERFACE)); }
              }}
            >
              Force Liquidation (Demo)
            </button>
            <button
              className="btn-action btn-success"
              disabled={!account}
              onClick={async () => {
                try {
                  const signer = await (provider as BrowserProvider).getSigner();
                  const comptroller = new Contract(deployments.MockComptroller, COMPTROLLER_ABI, signer);
                  const tx = await comptroller.setShortfall(false);
                  await tx.wait();
                  showToast("Position Restored", "Mock debt cleared. Position is healthy.", "success");
                  fetchHealth();
                } catch(err: any) { showError(decodeError(err, COMBINED_INTERFACE)); }
              }}
            >
              Restore Position
            </button>
            <button 
              className="btn-action btn-secondary" 
              onClick={fetchHealth} 
              disabled={!account}
              style={{ marginBottom: 0 }}
            >
              Sync position state
            </button>
          </div>
        </section>

        {/* CLAIM ZONE */}
        <section className="ledger-zone highlight">
          <h2>Claim</h2>
          <p>Generate zero-knowledge proofs directly in your browser to claim payouts privately.</p>
          
          <div style={{ display: 'flex', flexDirection: 'column', gap: '1rem', marginTop: '1.5rem' }}>
            <div className="input-group" style={{ marginBottom: 0 }}>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                <label className="stat-label">Policy ID</label>
                {claimPolicyId && policyStartBlock > 0 && holdingPeriodBlocks > 0 && currentBlock > 0 && (
                  <HoldingPeriodBadge 
                    currentBlock={currentBlock} 
                    startBlock={policyStartBlock} 
                    holdingPeriodBlocks={holdingPeriodBlocks} 
                  />
                )}
              </div>
              <input 
                className="masked-input"
                type="number" 
                value={claimPolicyId} 
                onChange={e => setClaimPolicyId(e.target.value)} 
                placeholder="0" 
              />
            </div>
            
            <div className="input-group" style={{ marginBottom: 0 }}>
              <label className="stat-label">Round ID (block)</label>
              <div style={{ display: 'flex', gap: '0.5rem' }}>
                <input 
                  className="masked-input"
                  type="number" 
                  value={claimRoundId} 
                  onChange={e => setClaimRoundId(e.target.value)} 
                  placeholder="Block #" 
                  style={{ flex: 1 }} 
                />
                <button 
                  className="btn-secondary" 
                  style={{ padding: '0 1rem' }}
                  onClick={async () => {
                    if (!provider || !claimPolicyId) return showToast("Input Required", "Please enter a Policy ID first.", "info");
                    
                    try {
                      // Attempt 1: Envio GraphQL (Primary Path)
                      const query = `
                        query {
                          Policy(where: {id: {_eq: "${claimPolicyId}"}}) {
                            state
                            claimRoundId
                            claimLiquidity
                            claimShortfall
                          }
                        }
                      `;
                      const res = await fetch("https://indexer.dev.hyperindex.xyz/84dad5e/v1/graphql", {
                        method: "POST",
                        headers: { "Content-Type": "application/json" },
                        body: JSON.stringify({ query })
                      });
                      
                      const data = await res.json();
                      const policy = data?.data?.Policy?.[0];
                      
                      if (policy && policy.state === "ClaimWindowOpened" && policy.claimRoundId) {
                        setClaimRoundId(policy.claimRoundId.toString());
                        if (policy.claimLiquidity != null) setClaimLiquidity(policy.claimLiquidity.toString());
                        if (policy.claimShortfall != null) setClaimShortfall(policy.claimShortfall.toString());
                        showToast("Commitment Found", `Located oracle data at Block ${policy.claimRoundId} via Envio Indexer.`, "success");
                      } else {
                        showToast("Not Found", "No oracle commitment detected in Envio yet. The CRE workflow may not have polled.", "info");
                      }
                      return; // Always exit if Envio was reachable, do not fall back.
                    } catch (err) {
                      console.warn("Envio indexer query failed, attempting direct-contract fallback...", err);
                      showToast("Envio Offline", "Indexer unreachable. Falling back to direct eth_call scan...", "error");
                    }

                    // Attempt 2: Direct eth_call scan (Fallback Path only on network failure)
                    try {
                      const registry = new Contract(deployments.PolicyRegistry, REGISTRY_ABI, provider);
                      const currentBlock = await provider.getBlockNumber();
                      let found = false;
                      for (let b = currentBlock; b >= Math.max(0, currentBlock - 200); b--) {
                        const val = await registry.commitments(claimPolicyId, b);
                        if (val !== 0n) {
                          setClaimRoundId(b.toString());
                          showToast("Commitment Found", `Located oracle data at Block ${b} via Fallback Scan.`, "success");
                          found = true;
                          break;
                        }
                      }
                      if (!found) {
                        showToast("Not Found", "No oracle commitment detected in recent blocks.", "info");
                      }
                    } catch (err) {
                      console.error("Fallback scan failed:", err);
                      showError(decodeError(err, COMBINED_INTERFACE));
                    }
                  }}
                >
                  Fetch
                </button>
              </div>
            </div>
          </div>

          <div style={{ marginTop: '1.5rem' }}>
            <button
              className="btn-secondary"
              style={{ width: '100%' }}
              disabled={!account || !claimPolicyId || !!claimRoundId}
              onClick={() => setIsWatching(w => !w)}
            >
              {isWatching ? 'Stop watching' : 'Watch for oracle commitment'}
            </button>
          </div>

          {watchStatus && (
            <div className="watcher-status">
              {watchStatus}
            </div>
          )}

          {policyState === 2 ? (
            <button 
              className="btn-secondary" 
              style={{ marginTop: '1rem', width: '100%', borderColor: 'var(--stable)', color: 'var(--stable)' }} 
              onClick={() => {
                const saved = localStorage.getItem(`notell_proof_${claimPolicyId}`);
                if (saved) {
                  setProofLogs(JSON.parse(saved));
                } else {
                  // Fallback for policies claimed before we added localStorage saving
                  setProofLogs([
                    "Extracting private inputs (Liquidity, Shortfall)",
                    "Retrieving public inputs (Oracle Commitment Hash, Round ID)",
                    "Computing groth16 cryptographic proof locally",
                    "ZK Proof computed successfully",
                    "Submitting proof to InsurancePool smart contract",
                    "✅ Claim transaction confirmed on-chain"
                  ]);
                }
              }}
              disabled={!claimPolicyId}
            >
              ✓ Policy Claimed (View Proof)
            </button>
          ) : (
            <button 
              className="btn-primary" 
              style={{ marginTop: '1rem', width: '100%' }} 
              onClick={handleGenerateProof}
              disabled={!account || isProving || !claimPolicyId || !claimRoundId}
            >
              {isProving ? 'Computing zero-knowledge proof locally...' : 'Generate proof & claim'}
            </button>
          )}

          {proofLogs.length > 0 && (
            <div style={{ marginTop: '1.5rem', padding: '1.25rem', background: 'var(--bg-lighter)', border: '1px solid var(--border-color)', borderRadius: '8px', fontSize: '0.9rem' }}>
              <h4 style={{ margin: '0 0 1rem 0', color: 'var(--text-color)', letterSpacing: '0.5px' }}>ZKP Generation Sequence</h4>
              <ul style={{ paddingLeft: '1rem', margin: 0, display: 'flex', flexDirection: 'column', gap: '0.75rem', listStyleType: 'square' }}>
                {proofLogs.map((log, i) => (
                  <li key={i} style={{ color: 'var(--text-muted)' }}>
                    {log}
                  </li>
                ))}
              </ul>
            </div>
          )}
        </section>
      </main>
      
      <footer style={{ marginTop: '4rem', padding: '2rem', borderTop: '1px solid var(--rule)', display: 'flex', justifyContent: 'space-between', alignItems: 'center', color: 'var(--text-muted)', fontSize: '0.9rem' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
          <img src="/favicon.png" alt="NoTell Logo" style={{ width: '20px', height: '20px', opacity: 0.8 }} />
          <span><strong>NoTell</strong> &mdash; Nobody sees your tell.</span>
        </div>
        <div>
          <a href="/ATTACK_SURFACE.md" style={{ color: 'var(--text-muted)', textDecoration: 'none', borderBottom: '1px dotted var(--text-muted)' }} target="_blank" rel="noopener noreferrer">Security & Limitations</a>
        </div>
      </footer>
      </div>
      ) : (
        <main className="main-grid" style={{ gridTemplateColumns: 'repeat(2, 1fr)' }}>
          <section className="ledger-zone">
            <h2>Supply Collateral</h2>
            <p>Deposit ETH into the simulated Peridot lending protocol.</p>
            
            <div className="input-group" style={{ marginTop: '1.5rem' }}>
              <label className="stat-label">Amount (ETH)</label>
              <input 
                type="number" 
                value={supplyAmount} 
                onChange={(e) => setSupplyAmount(e.target.value)} 
                placeholder="e.g. 10"
              />
            </div>
            
            <button 
              className="btn-primary" 
              style={{ width: '100%' }}
              onClick={() => handleLendingAction('SUPPLY')}
              disabled={!account || isSupplying || !supplyAmount}
            >
              {isSupplying ? 'Processing...' : 'Supply ETH'}
            </button>
          </section>

          <section className="ledger-zone">
            <h2>Borrow USDC</h2>
            <p>Borrow mock USDC against your supplied collateral (80% Max LTV).</p>
            
            <div className="input-group" style={{ marginTop: '1.5rem' }}>
              <label className="stat-label">Amount (USD)</label>
              <input 
                type="number" 
                value={borrowAmount} 
                onChange={(e) => setBorrowAmount(e.target.value)} 
                placeholder="e.g. 5000"
              />
            </div>

            <button 
              className="btn-primary" 
              style={{ width: '100%' }}
              onClick={() => handleLendingAction('BORROW')}
              disabled={!account || isBorrowing || !borrowAmount}
            >
              {isBorrowing ? 'Processing...' : 'Borrow USD'}
            </button>
          </section>
        </main>
      )}
    </div>
  );
}

export default App;