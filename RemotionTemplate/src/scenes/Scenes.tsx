import React from 'react';
import {AbsoluteFill, Img, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {KineticText} from '../components/KineticText';
import {PhoneFrame} from '../components/PhoneFrame';
import type {Brand, Scene} from '../types';
import type {ThemeStyle} from '../themes';

type SceneProps = {scene: Scene; brand: Brand; theme: ThemeStyle};

// The Reels UI covers the top ~220px and bottom ~420px; content stays inside this safe area.
const SAFE: React.CSSProperties = {
  paddingTop: 220,
  paddingBottom: 420,
  paddingLeft: 80,
  paddingRight: 80,
  alignItems: 'center',
};

const Subtitle: React.FC<{text?: string; theme: ThemeStyle; delay: number; size?: number}> = ({
  text,
  theme,
  delay,
  size = 46,
}) => {
  const frame = useCurrentFrame();
  if (!text) return null;
  const o = interpolate(frame - delay, [0, 12], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  return (
    <div
      style={{
        fontFamily: theme.bodyFamily,
        fontWeight: 500,
        fontSize: size,
        lineHeight: 1.3,
        color: 'rgba(255,255,255,0.88)',
        textAlign: 'center',
        opacity: o,
        transform: `translateY(${(1 - o) * 20}px)`,
        maxWidth: 880,
      }}
    >
      {text}
    </div>
  );
};

export const HookScene: React.FC<SceneProps> = ({scene, brand, theme}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const punch = spring({frame, fps, config: {damping: 9, stiffness: 120}});
  const scale = interpolate(punch, [0, 1], [1.25, 1]);
  return (
    <AbsoluteFill style={{...SAFE, justifyContent: 'center', gap: 50}}>
      {scene.emoji ? (
        <div style={{fontSize: 170, transform: `scale(${punch})`}}>{scene.emoji}</div>
      ) : null}
      <div style={{transform: `scale(${scale})`}}>
        <KineticText text={scene.title} brand={brand} theme={theme} size={112} highlight={theme.highlightBox} />
      </div>
      <Subtitle text={scene.subtitle} theme={theme} delay={14} size={50} />
    </AbsoluteFill>
  );
};

export const ScreenshotScene: React.FC<SceneProps> = ({scene, brand, theme}) => {
  const frame = useCurrentFrame();
  const {fps, durationInFrames} = useVideoConfig();
  const enter = spring({frame: frame - 4, fps, config: {damping: 16, stiffness: 90}});
  const y = interpolate(enter, [0, 1], [900, 0]);
  const tilt = interpolate(frame, [0, durationInFrames], [-7, 7]);
  const zoom = interpolate(frame, [0, durationInFrames], [1, 1.06]);
  return (
    <AbsoluteFill style={{...SAFE, justifyContent: 'flex-start', gap: 40}}>
      <KineticText text={scene.title} brand={brand} theme={theme} size={78} highlight={theme.highlightBox} />
      <Subtitle text={scene.subtitle} theme={theme} delay={10} size={40} />
      {scene.image ? (
        <div
          style={{
            transform: `translateY(${y}px) perspective(1600px) rotateY(${tilt}deg) scale(${zoom})`,
            marginTop: 10,
          }}
        >
          <PhoneFrame
            src={scene.image}
            width={scene.imageStyle === 'raw' ? 600 : 520}
            style={scene.imageStyle}
            glow={theme.glow ? brand.accent : undefined}
          />
        </div>
      ) : null}
    </AbsoluteFill>
  );
};

export const FeatureScene: React.FC<SceneProps> = ({scene, brand, theme}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const bullets = scene.bullets ?? [];
  return (
    <AbsoluteFill style={{...SAFE, justifyContent: 'center', gap: 50}}>
      <KineticText text={scene.title} brand={brand} theme={theme} size={86} highlight={theme.highlightBox} />
      <div style={{display: 'flex', flexDirection: 'column', gap: 28, width: '100%'}}>
        {bullets.map((b, i) => {
          const s = spring({frame: frame - 14 - i * 9, fps, config: {damping: 14}});
          return (
            <div
              key={i}
              style={{
                display: 'flex',
                alignItems: 'center',
                gap: 28,
                padding: '30px 36px',
                borderRadius: 32,
                backgroundColor: 'rgba(255,255,255,0.1)',
                border: `2px solid ${brand.primary}88`,
                opacity: s,
                transform: `translateX(${interpolate(s, [0, 1], [i % 2 ? 300 : -300, 0])}px)`,
                fontFamily: theme.bodyFamily,
                fontSize: 46,
                fontWeight: 600,
                color: '#fff',
              }}
            >
              <div
                style={{
                  minWidth: 64,
                  height: 64,
                  borderRadius: 32,
                  backgroundColor: brand.accent,
                  color: brand.background,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  fontWeight: 800,
                  fontSize: 36,
                }}
              >
                {i + 1}
              </div>
              {b}
            </div>
          );
        })}
      </div>
      {scene.image ? (
        <div style={{opacity: spring({frame: frame - 30, fps})}}>
          <PhoneFrame src={scene.image} width={300} style={scene.imageStyle} />
        </div>
      ) : null}
    </AbsoluteFill>
  );
};

export const StatScene: React.FC<SceneProps> = ({scene, brand, theme}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const raw = scene.stat ?? '';
  const match = raw.match(/^([^0-9]*)([0-9]+(?:[.,][0-9]+)?)(.*)$/);
  const progress = spring({frame, fps, durationInFrames: 40, config: {damping: 200}});
  let display = raw;
  if (match) {
    const target = parseFloat(match[2].replace(',', '.'));
    const decimals = match[2].includes('.') || match[2].includes(',') ? 1 : 0;
    display = `${match[1]}${(target * progress).toFixed(decimals)}${match[3]}`;
  }
  return (
    <AbsoluteFill style={{...SAFE, justifyContent: 'center', gap: 30}}>
      <div
        style={{
          fontFamily: theme.fontFamily,
          fontWeight: 900,
          fontSize: 240,
          color: brand.accent,
          textShadow: theme.glow ? `0 0 80px ${brand.accent}` : `0 20px 60px rgba(0,0,0,0.4)`,
          transform: `scale(${interpolate(progress, [0, 1], [0.6, 1])})`,
        }}
      >
        {display}
      </div>
      <KineticText text={scene.title} brand={brand} theme={theme} size={70} delay={10} />
      <Subtitle text={scene.subtitle} theme={theme} delay={20} />
    </AbsoluteFill>
  );
};

export const CtaScene: React.FC<SceneProps> = ({scene, brand, theme}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const pop = spring({frame, fps, config: {damping: 10}});
  const pulse = 1 + 0.04 * Math.sin(frame / 5);
  return (
    <AbsoluteFill style={{...SAFE, justifyContent: 'center', gap: 50}}>
      {brand.logo ? (
        <Img
          src={staticFile(brand.logo)}
          style={{width: 260, height: 260, borderRadius: 60, transform: `scale(${pop})`, boxShadow: '0 30px 90px rgba(0,0,0,0.5)'}}
        />
      ) : null}
      <KineticText text={scene.title} brand={brand} theme={theme} size={96} delay={6} highlight={theme.highlightBox} />
      <Subtitle text={scene.subtitle} theme={theme} delay={14} />
      <div
        style={{
          marginTop: 20,
          padding: '34px 70px',
          borderRadius: 100,
          backgroundColor: brand.accent,
          color: brand.background,
          fontFamily: theme.fontFamily,
          fontWeight: 800,
          fontSize: 50,
          transform: `scale(${spring({frame: frame - 18, fps}) * pulse})`,
          boxShadow: `0 0 60px ${brand.accent}88`,
        }}
      >
        {brand.storeLabel ?? 'App Store’da indir'}
      </div>
    </AbsoluteFill>
  );
};

export const SCENE_COMPONENTS: Record<Scene['kind'], React.FC<SceneProps>> = {
  hook: HookScene,
  screenshot: ScreenshotScene,
  feature: FeatureScene,
  stat: StatScene,
  cta: CtaScene,
};
