import React from 'react';
import './LandingPage.css';

interface LandingPageProps {
  onLaunchApp: () => void;
}

export const LandingPage: React.FC<LandingPageProps> = ({ onLaunchApp }) => {
  return (
    <div className="landing-pg">
      {/* Navigation */}
      <nav className="landing-in" style={{
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        gap: '16px',
        flexWrap: 'wrap',
        paddingTop: '22px',
        paddingBottom: '22px'
      }}>
        <a href="#top" className="landing-ser" style={{
          display: 'flex',
          alignItems: 'center',
          gap: '12px',
          fontSize: '24px',
          fontWeight: 600
        }}>
          <svg width="34" height="34" viewBox="0 0 120 120" role="img" aria-label="NoTell logo">
            <rect x="2" y="2" width="116" height="116" rx="22" fill="#141715" stroke="#2A2F2B" strokeWidth="3" />
            <path d="M30 28h13v64H30zM77 28h13v64H77zM30 28h15l45 64H75z" fill="#F2F0E9" />
            <rect x="18" y="56" width="84" height="8" fill="#141715" />
            <rect x="22" y="58" width="76" height="4" rx="1" fill="#5E8C6A" />
          </svg>
          NoTell
        </a>

        <div className="landing-mut" style={{ display: 'flex', gap: '28px', fontSize: '15px' }}>
          <a href="#flow">Lifecycle</a>
          <a href="#real">Real vs simulated</a>
          <a href="https://github.com/raj-1106/NoTell" target="_blank" rel="noopener noreferrer">Code</a>
        </div>

        <button className="landing-btn landing-btn2" onClick={onLaunchApp}>
          Launch app
        </button>
      </nav>

      {/* Hero Section */}
      <section id="top" className="landing-hero">
        <div className="landing-in" style={{ textAlign: 'center', paddingTop: '88px', paddingBottom: '96px' }}>
          <span className="landing-mono landing-mut" style={{ fontSize: '13px', letterSpacing: '.08em', display: 'inline-block', marginBottom: '16px' }}>
            LIQUIDATION COVER · MONAD TESTNET
          </span>
          <h1 className="landing-ser" style={{
            fontWeight: 600,
            fontSize: 'clamp(42px, 6vw, 76px)',
            lineHeight: 1.04,
            letterSpacing: '-.025em',
            margin: '0 auto 24px',
            maxWidth: '900px',
            background: '#0E1210',
            display: 'inline-block',
            padding: '0 12px'
          }}>
            Insurance you claim with a proof.
          </h1>
          <p className="landing-mut" style={{
            fontSize: 'clamp(17px, 2vw, 20px)',
            lineHeight: 1.6,
            margin: '0 auto 40px',
            maxWidth: '640px',
            background: '#0E1210'
          }}>
            NoTell covers crypto borrowers against liquidation. A claim is a zero-knowledge proof generated in your browser and verified on-chain, not a form and not a vote.
          </p>
          <div style={{ display: 'flex', gap: '12px', justifyContent: 'center', flexWrap: 'wrap' }}>
            <button className="landing-btn landing-btn1" onClick={onLaunchApp}>
              Launch app
            </button>
            <a
              className="landing-btn landing-btn2"
              href="https://github.com/raj-1106/NoTell"
              target="_blank"
              rel="noopener noreferrer"
            >
              Read the code
            </a>
          </div>
        </div>
      </section>

      {/* Lifecycle Flow */}
      <section id="flow" className="landing-in" style={{ paddingTop: '40px', paddingBottom: '88px' }}>
        <div className="landing-mono landing-k" style={{ marginBottom: '36px' }}>CLAIM LIFECYCLE</div>
        <div style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(190px, 1fr))',
          gap: '28px'
        }}>
          <div className="landing-node">
            <div className="landing-k landing-mono">BLOCK 0</div>
            <div className="landing-ser" style={{ fontSize: '22px', margin: '8px 0' }}>Buy cover</div>
            <div className="landing-mut" style={{ fontSize: '15px', lineHeight: 1.55 }}>
              Pay a 1% premium. The policy is recorded on-chain.
            </div>
          </div>
          <div className="landing-node">
            <div className="landing-k landing-mono">BLOCK +288,000</div>
            <div className="landing-ser" style={{ fontSize: '22px', margin: '8px 0' }}>Holding period ends</div>
            <div className="landing-mut" style={{ fontSize: '15px', lineHeight: 1.55 }}>
              About 25 hours. Claims open. No bypass.
            </div>
          </div>
          <div className="landing-node bad">
            <div className="landing-k landing-mono" style={{ color: '#C6482B' }}>SHORTFALL</div>
            <div className="landing-ser" style={{ fontSize: '22px', margin: '8px 0' }}>Position goes under</div>
            <div className="landing-mut" style={{ fontSize: '15px', lineHeight: 1.55 }}>
              The lending market reports a shortfall.
            </div>
          </div>
          <div className="landing-node">
            <div className="landing-k landing-mono">COMMITMENT</div>
            <div className="landing-ser" style={{ fontSize: '22px', margin: '8px 0' }}>Oracle posts a hash</div>
            <div className="landing-mut" style={{ fontSize: '15px', lineHeight: 1.55 }}>
              A keeper commits the state the proof must match.
            </div>
          </div>
          <div className="landing-node">
            <div className="landing-k landing-mono">PROOF AND PAYOUT</div>
            <div className="landing-ser" style={{ fontSize: '22px', margin: '8px 0' }}>Verified on-chain</div>
            <div className="landing-mut" style={{ fontSize: '15px', lineHeight: 1.55 }}>
              Your browser proves it, the contract pays you.
            </div>
          </div>
        </div>
      </section>

      {/* Metrics Grid */}
      <section className="landing-in" style={{ paddingBottom: '88px' }}>
        <div style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))',
          borderTop: '1px solid #2A2F2B',
          borderBottom: '1px solid #2A2F2B'
        }}>
          <div style={{ padding: '32px 24px', borderRight: '1px solid #2A2F2B' }}>
            <div className="landing-mono" style={{ fontSize: '44px' }}>1%</div>
            <div className="landing-mut" style={{ marginTop: '6px', fontSize: '15px' }}>Premium on cover</div>
          </div>
          <div style={{ padding: '32px 24px', borderRight: '1px solid #2A2F2B' }}>
            <div className="landing-mono" style={{ fontSize: '44px' }}>10%</div>
            <div className="landing-mut" style={{ marginTop: '6px', fontSize: '15px' }}>Fixed payout on a valid claim</div>
          </div>
          <div style={{ padding: '32px 24px', borderRight: '1px solid #2A2F2B' }}>
            <div className="landing-mono" style={{ fontSize: '44px' }}>288,000</div>
            <div className="landing-mut" style={{ marginTop: '6px', fontSize: '15px' }}>Blocks of holding period</div>
          </div>
          <div style={{ padding: '32px 24px' }}>
            <div className="landing-mono" style={{ fontSize: '44px' }}>Groth16</div>
            <div className="landing-mut" style={{ marginTop: '6px', fontSize: '15px' }}>Proof system, checked on-chain</div>
          </div>
        </div>
      </section>

      {/* Real vs Simulated */}
      <section id="real" className="landing-in" style={{ paddingBottom: '88px' }}>
        <h2 className="landing-ser" style={{ fontWeight: 400, fontSize: '34px', margin: '0 0 32px' }}>
          What is real, what is simulated
        </h2>
        <div style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))',
          gap: '20px'
        }}>
          <div className="landing-pane">
            <div className="landing-mono" style={{ fontSize: '13px', color: '#5E8C6A', marginBottom: '16px' }}>
              REAL
            </div>
            <div className="landing-li"><span>Contracts on Monad testnet</span></div>
            <div className="landing-li"><span>25-hour holding period</span></div>
            <div className="landing-li"><span>In-browser Groth16 proofs</span></div>
            <div className="landing-li"><span>On-chain proof verification</span></div>
            <div className="landing-li"><span>Envio indexer</span></div>
          </div>
          <div className="landing-pane">
            <div className="landing-mono" style={{ fontSize: '13px', color: '#C6482B', marginBottom: '16px' }}>
              SIMULATED
            </div>
            <div className="landing-li"><span>The lending market</span><span className="landing-mut landing-mono" style={{ fontSize: '13px' }}>mock</span></div>
            <div className="landing-li"><span>Oracle commitments</span><span className="landing-mut landing-mono" style={{ fontSize: '13px' }}>team-run keeper</span></div>
            <p className="landing-mut" style={{ fontSize: '14px', lineHeight: 1.6, margin: '16px 0 0' }}>
              Chainlink CRE does not yet support production writes on Monad testnet, so a keeper script posts commitments instead.
            </p>
          </div>
        </div>
      </section>

      {/* Bottom CTA Card */}
      <section className="landing-in" style={{ paddingBottom: '72px' }}>
        <div className="landing-pane" style={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          gap: '24px',
          flexWrap: 'wrap',
          padding: '36px'
        }}>
          <div>
            <div className="landing-ser" style={{ fontSize: '28px' }}>Try it on testnet</div>
            <p className="landing-mut" style={{ margin: '8px 0 0', fontSize: '15px' }}>
              Testnet only. Known limitations are documented in the repository.
            </p>
          </div>
          <button className="landing-btn landing-btn1" onClick={onLaunchApp}>
            Launch app
          </button>
        </div>
      </section>
    </div>
  );
};
