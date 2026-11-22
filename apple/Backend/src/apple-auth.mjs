const encoder = new TextEncoder();
let keyCache, keyExpires = 0;
export function randomToken() {
  return Array.from(crypto.getRandomValues(new Uint8Array(32)), n => n.toString(16).padStart(2, '0')).join('');
}
export async function digest(value) {
  return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(value))), n => n.toString(16).padStart(2, '0')).join('');
}
function decode(value) {
  return Uint8Array.from(atob(value.replace(/-/g, '+').replace(/_/g, '/')), c => c.charCodeAt(0));
}
export async function verifyAppleToken(token, {audience, nonce, now = Date.now() / 1000, keys}) {
  const parts = String(token).split('.');
  if (parts.length !== 3 || token.length > 16000) throw new Error('Invalid Apple token');
  const header = JSON.parse(new TextDecoder().decode(decode(parts[0])));
  const claims = JSON.parse(new TextDecoder().decode(decode(parts[1])));
  if (header.alg !== 'RS256' || typeof header.kid !== 'string') throw new Error('Invalid token algorithm');
  if (!keys) {
    if (!keyCache || now >= keyExpires || !keyCache.some(key => key.kid === header.kid)) {
      const response = await fetch('https://appleid.apple.com/auth/keys');
      if (!response.ok) throw new Error('Apple keys unavailable');
      keyCache = (await response.json()).keys; keyExpires = now + 3600;
    }
    keys = keyCache;
  }
  const jwk = keys.find(key => key.kid === header.kid && key.kty === 'RSA');
  if (!jwk) throw new Error('Unknown Apple key');
  const key = await crypto.subtle.importKey('jwk', jwk, {name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256'}, false, ['verify']);
  const valid = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, decode(parts[2]), encoder.encode(parts[0] + '.' + parts[1]));
  if (!valid || claims.iss !== 'https://appleid.apple.com' || claims.aud !== audience
    || !Number.isFinite(claims.exp) || claims.exp <= now || !Number.isFinite(claims.iat)
    || claims.iat > now + 60 || claims.iat < now - 600 || claims.nonce !== nonce
    || typeof claims.sub !== 'string' || !claims.sub || claims.sub.length > 255
    || ![true, 'true'].includes(claims.email_verified) || typeof claims.email !== 'string')
    throw new Error('Apple identity could not be verified');
  return claims;
}
