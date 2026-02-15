"use client";

import { useActionState, useState } from "react";
import { signIn, signUp } from "./actions";

export default function LoginPage() {
  const [isSignUp, setIsSignUp] = useState(false);
  const [signInState, signInAction, signInPending] = useActionState(signIn, null);
  const [signUpState, signUpAction, signUpPending] = useActionState(signUp, null);

  const action = isSignUp ? signUpAction : signInAction;
  const pending = isSignUp ? signUpPending : signInPending;
  const state = isSignUp ? signUpState : signInState;

  return (
    <div style={{ maxWidth: 400, margin: "100px auto", fontFamily: "system-ui" }}>
      <h1>{isSignUp ? "Sign Up" : "Sign In"}</h1>
      <form action={action}>
        <div style={{ marginBottom: 12 }}>
          <input
            name="email"
            type="email"
            placeholder="Email"
            required
            style={{ width: "100%", padding: 8, boxSizing: "border-box" }}
          />
        </div>
        <div style={{ marginBottom: 12 }}>
          <input
            name="password"
            type="password"
            placeholder="Password"
            required
            minLength={6}
            style={{ width: "100%", padding: 8, boxSizing: "border-box" }}
          />
        </div>
        <button
          type="submit"
          disabled={pending}
          style={{ width: "100%", padding: 10, cursor: "pointer" }}
        >
          {pending ? "..." : isSignUp ? "Sign Up" : "Sign In"}
        </button>
      </form>
      {state?.error && (
        <p style={{ marginTop: 12, color: "red" }}>{state.error}</p>
      )}
      {state && "message" in state && state.message && (
        <p style={{ marginTop: 12, color: "#666" }}>{state.message}</p>
      )}
      <p style={{ marginTop: 16 }}>
        {isSignUp ? "Already have an account?" : "Need an account?"}{" "}
        <button
          onClick={() => setIsSignUp(!isSignUp)}
          style={{
            background: "none",
            border: "none",
            color: "blue",
            cursor: "pointer",
            textDecoration: "underline",
            padding: 0,
          }}
        >
          {isSignUp ? "Sign In" : "Sign Up"}
        </button>
      </p>
    </div>
  );
}
