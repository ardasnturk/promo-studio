import React from 'react';
import {AbsoluteFill, interpolate, useCurrentFrame, useVideoConfig} from 'remotion';
import type {Brand} from '../types';
import type {ThemeStyle} from '../themes';

export const Background: React.FC<{brand: Brand; theme: ThemeStyle}> = ({brand, theme}) => {
  const frame = useCurrentFrame();
  const {width, height} = useVideoConfig();

  if (theme.background === 'solid') {
    return <AbsoluteFill style={{backgroundColor: brand.background}} />;
  }

  if (theme.background === 'gradient') {
    const angle = interpolate(frame, [0, 600], [140, 220]);
    return (
      <AbsoluteFill
        style={{
          background: `linear-gradient(${angle}deg, ${brand.background} 0%, ${brand.primary}55 55%, ${brand.background} 100%)`,
        }}
      />
    );
  }

  if (theme.background === 'grid') {
    const offset = (frame * 2) % 80;
    return (
      <AbsoluteFill style={{backgroundColor: brand.background, overflow: 'hidden'}}>
        <AbsoluteFill
          style={{
            backgroundImage: `linear-gradient(${brand.primary}33 2px, transparent 2px), linear-gradient(90deg, ${brand.primary}33 2px, transparent 2px)`,
            backgroundSize: '80px 80px',
            backgroundPosition: `0 ${offset}px`,
            transform: 'perspective(900px) rotateX(55deg) scale(2.2) translateY(20%)',
            transformOrigin: 'center bottom',
          }}
        />
        <AbsoluteFill
          style={{background: `radial-gradient(circle at 50% 30%, ${brand.accent}40, transparent 60%)`}}
        />
      </AbsoluteFill>
    );
  }

  // blobs
  const blob = (i: number, color: string) => {
    const t = frame / 40 + i * 2.1;
    const x = width * (0.5 + 0.35 * Math.sin(t * 0.9 + i));
    const y = height * (0.5 + 0.3 * Math.cos(t * 0.7 + i * 1.7));
    const size = width * (0.9 + 0.2 * Math.sin(t));
    return (
      <div
        key={i}
        style={{
          position: 'absolute',
          left: x - size / 2,
          top: y - size / 2,
          width: size,
          height: size,
          borderRadius: '50%',
          background: color,
          filter: 'blur(140px)',
          opacity: 0.55,
        }}
      />
    );
  };
  return (
    <AbsoluteFill style={{backgroundColor: brand.background, overflow: 'hidden'}}>
      {blob(0, brand.primary)}
      {blob(1, brand.accent)}
      {blob(2, brand.primary)}
    </AbsoluteFill>
  );
};
