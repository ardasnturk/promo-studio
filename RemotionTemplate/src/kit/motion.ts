import {Easing, interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;

/** 0→1 spring entrance. `bouncy` adds a slight bounce. */
export const useEnter = (delay = 0, bouncy = false): number => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  return spring({frame: frame - delay, fps, config: bouncy ? {damping: 11, stiffness: 170} : {damping: 200}});
};

/** Exit that drops to 0 at the end of the scene (over the last `frames` frames). */
export const useExit = (durationInFrames: number, frames = 10): number => {
  const frame = useCurrentFrame();
  return interpolate(frame, [durationInFrames - frames, durationInFrames], [1, 0], clamp);
};

/** Eased 0→1 progress over frames [start, end]. */
export const useProgress = (start: number, end: number): number => {
  const frame = useCurrentFrame();
  return interpolate(frame, [start, end], [0, 1], {...clamp, easing: Easing.bezier(0.22, 1, 0.36, 1)});
};

/** Scale that pops up on a hit and settles back (e.g. a goal, a number burst). */
export const usePunch = (at: number, strength = 0.18): number => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const s = spring({frame: frame - at, fps, config: {damping: 9, stiffness: 220}});
  return 1 + strength * Math.max(0, 1 - s) * (frame >= at ? 1 : 0);
};

/**
 * Camera shake (pixels). Deterministic: depends only on the frame number.
 * Decays from `amount` pixels to zero between `from` and `to`.
 */
export const useShake = (from: number, to: number, amount = 18): {x: number; y: number} => {
  const frame = useCurrentFrame();
  if (frame < from || frame > to) return {x: 0, y: 0};
  const decay = 1 - (frame - from) / Math.max(1, to - from);
  const a = ((frame * 7919) % 13) / 6 - 1;
  const b = ((frame * 104729) % 11) / 5 - 1;
  return {x: a * amount * decay, y: b * amount * decay};
};

/** Scale for a slow zoom (Ken Burns). */
export const useDrift = (durationInFrames: number, from = 1, to = 1.08): number => {
  const frame = useCurrentFrame();
  return interpolate(frame, [0, durationInFrames], [from, to], clamp);
};
