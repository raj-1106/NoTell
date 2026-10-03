import { computeProtocolStep, STEP_COPY } from "../lib/protocolStep";
import type { StepInput, ProtocolStep } from "../lib/protocolStep";
import "./ProtocolGuide.css";

const ORDER: ProtocolStep[] = ["no_policy", "holding_period", "eligible_no_commitment", "commitment_posted", "claimed"];

export function ProtocolGuide(input: StepInput) {
  const current = computeProtocolStep(input);
  const currentIndex = ORDER.indexOf(current);

  return (
    <div className="protocol-guide">
      {ORDER.filter((s) => s !== "no_policy" || current === "no_policy").map((step) => {
        const stepIndex = ORDER.indexOf(step);
        const copy = STEP_COPY[step];
        const status = stepIndex < currentIndex ? "done" : stepIndex === currentIndex ? "current" : "upcoming";
        return (
          <div key={step} className={`protocol-guide__step protocol-guide__step--${status}`}>
            <div className="protocol-guide__title">{copy.title}</div>
            <div className="protocol-guide__desc">{copy.description}</div>
          </div>
        );
      })}
    </div>
  );
}
