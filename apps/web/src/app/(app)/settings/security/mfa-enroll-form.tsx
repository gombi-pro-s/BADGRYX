"use client";

import { useEffect, useState, useTransition } from "react";
import { enrollTotpFactorAction, verifyTotpEnrollmentAction, type EnrollTotpState } from "./actions";
import { Button } from "@/components/ui/button";
import { FormError, Input, Label } from "@/components/ui/input";

const enrollInitialState: EnrollTotpState = { error: null, factorId: null, qrCode: null, secret: null };

export function MfaEnrollForm() {
  const [adding, setAdding] = useState(false);
  const [enrollState, setEnrollState] = useState(enrollInitialState);
  const [enrollPending, startEnroll] = useTransition();

  // Kicks off enrollment as soon as the user opens the flow -- there's no
  // input to collect first, the server just needs to create the factor.
  useEffect(() => {
    if (adding && !enrollState.factorId) {
      startEnroll(async () => {
        const result = await enrollTotpFactorAction();
        setEnrollState(result);
      });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [adding]);

  if (!adding) {
    return (
      <Button type="button" variant="secondary" onClick={() => setAdding(true)}>
        Add authenticator app
      </Button>
    );
  }

  return (
    <div className="rounded-lg border border-border bg-background-subtle p-5">
      {enrollPending && !enrollState.factorId && <p className="text-sm text-foreground-subtle">Setting up...</p>}
      {enrollState.error && <FormError>{enrollState.error}</FormError>}
      {enrollState.factorId && enrollState.qrCode && (
        <VerifyStep
          factorId={enrollState.factorId}
          qrCode={enrollState.qrCode}
          secret={enrollState.secret}
          onVerified={() => {
            setAdding(false);
            setEnrollState(enrollInitialState);
          }}
          onCancel={() => {
            setAdding(false);
            setEnrollState(enrollInitialState);
          }}
        />
      )}
    </div>
  );
}

function VerifyStep({
  factorId,
  qrCode,
  secret,
  onVerified,
  onCancel,
}: {
  factorId: string;
  qrCode: string;
  secret: string | null;
  onVerified: () => void;
  onCancel: () => void;
}) {
  const [code, setCode] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startVerify] = useTransition();

  function submit() {
    const formData = new FormData();
    formData.set("code", code);
    startVerify(async () => {
      const result = await verifyTotpEnrollmentAction(factorId, { error: null }, formData);
      if (result.error) {
        setError(result.error);
      } else {
        onVerified();
      }
    });
  }

  return (
    <div className="space-y-4">
      <p className="text-sm text-foreground-muted">
        Scan this QR code with your authenticator app (Google Authenticator, 1Password, Authy, etc.), then enter the
        6-digit code it shows.
      </p>
      {/* An SVG data URI generated per-enrollment by Supabase Auth, not a static asset -- next/image can't optimize a data: URI, so this uses a plain <img>. */}
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={qrCode} alt="Scan with your authenticator app" className="h-40 w-40 rounded-md bg-white p-2" />
      {secret && (
        <p className="text-xs text-foreground-subtle">
          Can&apos;t scan? Enter this code manually: <code className="rounded bg-surface px-1.5 py-0.5">{secret}</code>
        </p>
      )}
      <div className="space-y-3">
        <div>
          <Label htmlFor="code">6-digit code</Label>
          <Input
            id="code"
            name="code"
            type="text"
            inputMode="numeric"
            pattern="[0-9]{6}"
            maxLength={6}
            placeholder="123456"
            value={code}
            onChange={(e) => setCode(e.target.value)}
            required
          />
        </div>
        <FormError>{error}</FormError>
        <div className="flex gap-2">
          <Button type="button" disabled={pending || code.length !== 6} onClick={submit}>
            {pending ? "Verifying..." : "Verify & enable"}
          </Button>
          <Button type="button" variant="secondary" onClick={onCancel}>
            Cancel
          </Button>
        </div>
      </div>
    </div>
  );
}
