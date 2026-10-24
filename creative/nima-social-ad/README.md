# Nima social ad

Code-driven 1080 × 1920 paid-social creative built with Remotion.

## Timing

- 0.0–3.4s: Instagram/Reels hook and before/blocked proof
- 3.4–8.9s: TikTok For You Page before/blocked proof
- 8.9–13.6s: Screen Time problem
- 13.4–17.5s: Nima product solution
- 17.4–21.0s: Instagram DMs remain available
- 20.8–24.0s: brand payoff and download CTA

The overlapping scene boundaries are intentional and produce the soft, energetic transitions.

## Commands

Use a modern Node.js version, then run:

```bash
pnpm install
pnpm studio
pnpm render
```

The main composition is `NimaSocialAd` in `src/NimaSocialAd.tsx`. Source media lives in `public/assets`.

## Output

The finished master is rendered to `out/nima-social-ad.mp4` at 30fps with H.264 video and AAC audio.
