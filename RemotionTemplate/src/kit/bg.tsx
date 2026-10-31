import React from 'react';
import {AbsoluteFill, interpolate, random, useCurrentFrame, useVideoConfig} from 'remotion';

/** Slowly rotating two-color gradient. */
export const GradientBg: React.FC<{from: string; to: string; base?: string}> = ({from, to, base = '#000'}) => {
  const frame = useCurrentFrame();
  const angle = interpolate(frame, [0, 900], [135, 225]);
  return <AbsoluteFill style={{background: `linear-gradient(${angle}deg, ${from} 0%, ${base} 55%, ${to} 100%)`}} />;
};

/** Spotlight glowing in the center (stadium light, stage highlight). */
export const Spotlight: React.FC<{color: string; base: string; x?: number; y?: number; size?: number; pulse?: boolean}> = ({
  color,
  base,
  x = 50,
  y = 35,
  size = 60,
  pulse = false,
}) => {
  const frame = useCurrentFrame();
  const k = pulse ? 1 + 0.08 * Math.abs(((frame % 60) - 30) / 30) : 1;
  return <AbsoluteFill style={{background: `radial-gradient(circle at ${x}% ${y}%, ${color} 0%, ${base} ${size * k}%)`}} />;
};

/** Flowing perspective grid floor (tech / digital feel). */
export const GridFloor: React.FC<{color: string; base: string; speed?: number}> = ({color, base, speed = 2}) => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill style={{backgroundColor: base, overflow: 'hidden'}}>
      <AbsoluteFill
        style={{
          backgroundImage: `linear-gradient(${color}44 2px, transparent 2px), linear-gradient(90deg, ${color}44 2px, transparent 2px)`,
          backgroundSize: '80px 80px',
          backgroundPosition: `0 ${(frame * speed) % 80}px`,
          transform: 'perspective(900px) rotateX(58deg) scale(2.4) translateY(22%)',
          transformOrigin: 'center bottom',
        }}
      />
    </AbsoluteFill>
  );
};

/** Pitch markings (top-down football pitch) on a green background. */
export const Pitch: React.FC<{base?: string; line?: string}> = ({base = '#14532d', line = 'rgba(255,255,255,0.35)'}) => {
  const {width, height} = useVideoConfig();
  const stroke = 6;
  return (
    <AbsoluteFill style={{background: `repeating-linear-gradient(0deg, ${base} 0, ${base} 160px, #166534 160px, #166534 320px)`}}>
      <svg width={width} height={height} style={{position: 'absolute'}}>
        <rect x={60} y={120} width={width - 120} height={height - 240} fill="none" stroke={line} strokeWidth={stroke} />
        <line x1={60} y1={height / 2} x2={width - 60} y2={height / 2} stroke={line} strokeWidth={stroke} />
        <circle cx={width / 2} cy={height / 2} r={170} fill="none" stroke={line} strokeWidth={stroke} />
        <rect x={width / 2 - 260} y={120} width={520} height={260} fill="none" stroke={line} strokeWidth={stroke} />
        <rect x={width / 2 - 260} y={height - 380} width={520} height={260} fill="none" stroke={line} strokeWidth={stroke} />
      </svg>
    </AbsoluteFill>
  );
};

/** Deterministic floating particles (confetti, sparks, dust). Change `seed` for a different distribution. */
export const Particles: React.FC<{count?: number; colors: string[]; seed?: string; size?: number; speed?: number; start?: number}> = ({
  count = 40,
  colors,
  seed = 'p',
  size = 14,
  speed = 1,
  start = 0,
}) => {
  const frame = useCurrentFrame();
  const {width, height} = useVideoConfig();
  const t = Math.max(0, frame - start);
  return (
    <AbsoluteFill style={{pointerEvents: 'none'}}>
      {Array.from({length: count}).map((_, i) => {
        const x = random(`${seed}x${i}`) * width;
        const y0 = random(`${seed}y${i}`) * height;
        const v = (0.6 + random(`${seed}v${i}`)) * speed * 3;
        const y = (y0 - t * v + height * 4) % (height + 40);
        const s = size * (0.5 + random(`${seed}s${i}`));
        return (
          <div
            key={i}
            style={{
              position: 'absolute',
              left: x,
              top: y,
              width: s,
              height: s,
              borderRadius: s,
              backgroundColor: colors[i % colors.length],
              opacity: frame < start ? 0 : 0.85,
            }}
          />
        );
      })}
    </AbsoluteFill>
  );
};

/** Confetti burst: scatters from the center at frame `at`. */
export const Burst: React.FC<{at: number; colors: string[]; seed?: string; count?: number; x?: number; y?: number}> = ({
  at,
  colors,
  seed = 'b',
  count = 60,
  x = 540,
  y = 900,
}) => {
  const frame = useCurrentFrame();
  const t = frame - at;
  if (t < 0 || t > 60) return null;
  return (
    <AbsoluteFill style={{pointerEvents: 'none'}}>
      {Array.from({length: count}).map((_, i) => {
        const vx = (random(`${seed}vx${i}`) - 0.5) * 60;
        const vy = -random(`${seed}vy${i}`) * 55 - 10;
        const px = x + vx * t;
        const py = y + vy * t + 1.4 * t * t;
        const s = 10 + random(`${seed}s${i}`) * 16;
        return (
          <div
            key={i}
            style={{
              position: 'absolute',
              left: px,
              top: py,
              width: s,
              height: s * 0.6,
              backgroundColor: colors[i % colors.length],
              transform: `rotate(${t * 18 + i * 30}deg)`,
              opacity: interpolate(t, [40, 60], [1, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'}),
            }}
          />
        );
      })}
    </AbsoluteFill>
  );
};

/** White flash (hard cut / hit moment). Flashes at frame `at`. */
export const Flash: React.FC<{at: number; color?: string; frames?: number}> = ({at, color = '#fff', frames = 8}) => {
  const frame = useCurrentFrame();
  const o = interpolate(frame, [at, at + 1, at + frames], [0, 0.9, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  return <AbsoluteFill style={{backgroundColor: color, opacity: o, pointerEvents: 'none'}} />;
};

/** Subtle film grain and vignette that give the video a "shot on camera" texture. Place on top. */
export const Vignette: React.FC<{strength?: number}> = ({strength = 0.55}) => (
  <AbsoluteFill style={{pointerEvents: 'none', background: `radial-gradient(ellipse at center, transparent 45%, rgba(0,0,0,${strength}) 100%)`}} />
);
