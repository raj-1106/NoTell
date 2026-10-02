import { createContext, useCallback, useContext, useState, type ReactNode } from "react";
import type { FriendlyError } from "../lib/decodeError";

export type ToastType = 'error' | 'success' | 'info';

export interface ToastEntry {
  id: string;
  title: string;
  message: string;
  type: ToastType;
}

interface ErrorToastContextValue {
  showError: (error: FriendlyError) => void;
  showToast: (title: string, message: string, type: ToastType) => void;
  dismiss: (id: string) => void;
  toasts: ToastEntry[];
}

const ErrorToastContext = createContext<ErrorToastContextValue | null>(null);

const AUTO_DISMISS_MS = 8000;

export function ErrorToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<ToastEntry[]>([]);

  const dismiss = useCallback((id: string) => {
    setToasts((prev) => prev.filter((e) => e.id !== id));
  }, []);

  const showToast = useCallback((title: string, message: string, type: ToastType) => {
    const id = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
    setToasts((prev) => [...prev, { id, title, message, type }]);
    window.setTimeout(() => dismiss(id), AUTO_DISMISS_MS);
  }, [dismiss]);

  const showError = useCallback(
    (error: FriendlyError) => {
      const id = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
      setToasts((prev) => [...prev, { id, title: error.title, message: error.message, type: 'error' }]);
      // Debug detail always goes to console for real troubleshooting,
      // the toast itself never renders `error.debug`.
      console.error(`[NoTell] ${error.debug}`);
      window.setTimeout(() => dismiss(id), AUTO_DISMISS_MS);
    },
    [dismiss]
  );

  return (
    <ErrorToastContext.Provider value={{ showError, showToast, dismiss, toasts }}>
      {children}
    </ErrorToastContext.Provider>
  );
}

export function useErrorToast() {
  const ctx = useContext(ErrorToastContext);
  if (!ctx) throw new Error("useErrorToast must be used within ErrorToastProvider");
  return ctx;
}
