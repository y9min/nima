# iOS Tunnel Regression Matrix

Use this matrix before merge to prevent "fix one thing, break another" regressions.

## Toggle scenarios (must pass)
1. Both toggles OFF
- Expected: no content blocking decisions
- Expected: VPN auto-turns OFF (or does not auto-start)

2. Reels ON, Messages OFF
- Expected: reels/media paths blocked for enabled app(s)
- Expected: messaging control plane allowed

3. Reels OFF, Messages ON
- Expected: messaging paths blocked per policy
- Expected: reels/media not blocked solely by reels rules

4. Both toggles ON
- Expected: both reels/media and messaging policies enforced

## Transport/decoder sanity
- UDP decoder should not continuously churn with decode errors under normal traffic
- No runaway connection churn after policy settles

## Release decision
- Any failed scenario blocks merge.
