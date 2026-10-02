import { useErrorToast } from "../context/ErrorToastContext";
import "./ErrorToastStack.css";

export function ErrorToastStack() {
  const { toasts, dismiss } = useErrorToast();

  if (toasts.length === 0) return null;

  return (
    <div className="error-toast-stack" role="alert" aria-live="assertive">
      {toasts.map((err) => (
        <div key={err.id} className={`error-toast toast-${err.type}`}>
          <div className="error-toast__body">
            <span className="error-toast__title">{err.title}</span>
            <span className="error-toast__message">{err.message}</span>
          </div>
          <button
            className="error-toast__close"
            onClick={() => dismiss(err.id)}
            aria-label="Dismiss"
          >
            ×
          </button>
        </div>
      ))}
    </div>
  );
}
