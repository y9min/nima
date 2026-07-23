import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { decodeJwt, importPKCS8, SignJWT } from "npm:jose@5.9.6";

const jsonHeaders = {
  "Content-Type": "application/json",
};

function jsonResponse(body: Record<string, string>, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: jsonHeaders,
  });
}

async function requestBody(request: Request): Promise<Record<string, unknown>> {
  const text = await request.text();
  if (!text.trim()) {
    return {};
  }

  try {
    return JSON.parse(text);
  } catch {
    throw new Error("invalid_request_body");
  }
}

function requiredAppleConfiguration() {
  const clientId = Deno.env.get("APPLE_CLIENT_ID");
  const teamId = Deno.env.get("APPLE_TEAM_ID");
  const keyId = Deno.env.get("APPLE_KEY_ID");
  const privateKey = Deno.env.get("APPLE_PRIVATE_KEY")?.replaceAll("\\n", "\n");

  if (!clientId || !teamId || !keyId || !privateKey) {
    throw new Error("apple_revocation_not_configured");
  }

  return { clientId, teamId, keyId, privateKey };
}

async function createAppleClientSecret(
  configuration: ReturnType<typeof requiredAppleConfiguration>,
) {
  const signingKey = await importPKCS8(configuration.privateKey, "ES256");
  const now = Math.floor(Date.now() / 1000);

  return await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: configuration.keyId })
    .setIssuer(configuration.teamId)
    .setIssuedAt(now)
    .setExpirationTime(now + 300)
    .setAudience("https://appleid.apple.com")
    .setSubject(configuration.clientId)
    .sign(signingKey);
}

async function postToApple(path: string, body: URLSearchParams) {
  return await fetch(`https://appleid.apple.com${path}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body,
  });
}

async function revokeAppleAuthorization(
  authorizationCode: string,
  expectedAppleUserId: string,
) {
  const configuration = requiredAppleConfiguration();
  const clientSecret = await createAppleClientSecret(configuration);
  const tokenResponse = await postToApple("/auth/token", new URLSearchParams({
    client_id: configuration.clientId,
    client_secret: clientSecret,
    code: authorizationCode,
    grant_type: "authorization_code",
  }));

  if (!tokenResponse.ok) {
    throw new Error("apple_token_exchange_failed");
  }

  const tokenPayload = await tokenResponse.json();
  const idToken = tokenPayload.id_token;
  if (typeof idToken !== "string" || !idToken) {
    throw new Error("apple_identity_token_missing");
  }

  const appleUserId = decodeJwt(idToken).sub;
  if (!appleUserId || appleUserId !== expectedAppleUserId) {
    throw new Error("apple_account_mismatch");
  }

  const refreshToken = tokenPayload.refresh_token;
  if (typeof refreshToken !== "string" || !refreshToken) {
    throw new Error("apple_refresh_token_missing");
  }

  const revokeResponse = await postToApple("/auth/revoke", new URLSearchParams({
    client_id: configuration.clientId,
    client_secret: clientSecret,
    token: refreshToken,
    token_type_hint: "refresh_token",
  }));

  if (!revokeResponse.ok) {
    throw new Error("apple_token_revocation_failed");
  }
}

Deno.serve(async (request) => {
  if (request.method !== "DELETE") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const authorization = request.headers.get("authorization") ?? "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  const accessToken = match?.[1];

  if (!accessToken) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse({ error: "server_not_configured" }, 500);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  const { data: userData, error: userError } = await admin.auth.getUser(accessToken);
  if (userError || !userData.user) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  let body: Record<string, unknown>;
  try {
    body = await requestBody(request);
  } catch (error) {
    return jsonResponse({ error: error instanceof Error ? error.message : "invalid_request_body" }, 400);
  }

  const appleIdentity = userData.user.identities?.find(
    (identity) => identity.provider === "apple",
  );

  if (appleIdentity) {
    const authorizationCode = body.apple_authorization_code;
    if (typeof authorizationCode !== "string" || !authorizationCode) {
      return jsonResponse({ error: "apple_reauthorization_required" }, 409);
    }

    const identityData = appleIdentity.identity_data as Record<string, unknown> | undefined;
    const appleSubject = identityData?.sub;
    const expectedAppleUserId = typeof appleSubject === "string" && appleSubject
      ? appleSubject
      : appleIdentity.id;

    try {
      await revokeAppleAuthorization(authorizationCode, expectedAppleUserId);
    } catch (error) {
      return jsonResponse({
        error: error instanceof Error ? error.message : "apple_token_revocation_failed",
      }, 502);
    }
  }

  const { error: cleanupError } = await admin.rpc("delete_account_linked_rows", {
    target_user_id: userData.user.id,
  });

  if (cleanupError) {
    return jsonResponse({ error: cleanupError.message }, 500);
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(userData.user.id);
  if (deleteError) {
    return jsonResponse({ error: deleteError.message }, 500);
  }

  return new Response(null, { status: 204 });
});
