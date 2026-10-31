import React from 'react';
import {Img, interpolate, staticFile, useCurrentFrame} from 'remotion';
import {useEnter} from './motion';

/**
 * Shows a screenshot inside a phone frame.
 * `framed`: true if the image is an already-framed store screenshot (no frame is drawn).
 * `tilt`: 3D tilt in degrees; `float`: gentle floating.
 */
export const Phone: React.FC<{
  src: string;
  width: number;
  framed?: boolean;
  tilt?: number;
  float?: boolean;
  glow?: string;
  delay?: number;
  /** Vertical scroll within the screen (0–1): scroll-down effect for tall screenshots */
  scroll?: number;
}> = ({src, width, framed = false, tilt = 0, float = true, glow, delay = 0, scroll = 0}) => {
  const frame = useCurrentFrame();
  const enter = useEnter(delay);
  const bob = float ? interpolate(frame % 120, [0, 60, 120], [0, -14, 0]) : 0;
  const transform = `perspective(2000px) rotateY(${tilt}deg) translateY(${interpolate(enter, [0, 1], [260, 0]) + bob}px) scale(${interpolate(enter, [0, 1], [0.85, 1])})`;
  if (framed) {
    return (
      <Img
        src={staticFile(src)}
        style={{width, borderRadius: width * 0.06, opacity: enter, transform, boxShadow: `0 40px 120px rgba(0,0,0,0.55)${glow ? `, 0 0 90px ${glow}66` : ''}`}}
      />
    );
  }
  const height = width * 2.165;
  return (
    <div
      style={{
        width,
        height,
        borderRadius: width * 0.16,
        padding: width * 0.035,
        background: 'linear-gradient(145deg, #2b2b30, #0c0c0e)',
        boxShadow: `0 50px 140px rgba(0,0,0,0.6), inset 0 0 0 3px #3a3a40${glow ? `, 0 0 100px ${glow}66` : ''}`,
        opacity: enter,
        transform,
      }}
    >
      <div style={{width: '100%', height: '100%', borderRadius: width * 0.13, overflow: 'hidden', backgroundColor: '#000', position: 'relative'}}>
        <Img
          src={staticFile(src)}
          style={{width: '100%', minHeight: '100%', objectFit: 'cover', objectPosition: 'top', transform: `translateY(${-scroll * 40}%)`}}
        />
        <div
          style={{
            position: 'absolute',
            top: width * 0.03,
            left: '50%',
            transform: 'translateX(-50%)',
            width: width * 0.3,
            height: width * 0.085,
            borderRadius: width,
            backgroundColor: '#000',
          }}
        />
      </div>
    </div>
  );
};

/**
 * Zooms into a region of a screenshot (detail highlight).
 * focusX/focusY: focus point in 0–1; zoom: target magnification.
 */
export const ZoomShot: React.FC<{
  src: string;
  width: number;
  height: number;
  focusX?: number;
  focusY?: number;
  zoom?: number;
  start?: number;
  end?: number;
  radius?: number;
}> = ({src, width, height, focusX = 0.5, focusY = 0.3, zoom = 2, start = 0, end = 45, radius = 48}) => {
  const frame = useCurrentFrame();
  const t = interpolate(frame, [start, end], [0, 1], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  const scale = 1 + (zoom - 1) * t;
  return (
    <div style={{width, height, overflow: 'hidden', borderRadius: radius, boxShadow: '0 40px 120px rgba(0,0,0,0.5)'}}>
      <Img
        src={staticFile(src)}
        style={{width: '100%', height: '100%', objectFit: 'cover', objectPosition: 'top', transform: `scale(${scale})`, transformOrigin: `${focusX * 100}% ${focusY * 100}%`}}
      />
    </div>
  );
};

/** App icon / logo: rounded square with a spring entrance. */
export const AppIcon: React.FC<{src: string; size: number; delay?: number; glow?: string}> = ({src, size, delay = 0, glow}) => {
  const s = useEnter(delay, true);
  return (
    <Img
      src={staticFile(src)}
      style={{
        width: size,
        height: size,
        borderRadius: size * 0.225,
        transform: `scale(${s}) rotate(${interpolate(s, [0, 1], [-20, 0])}deg)`,
        boxShadow: `0 30px 80px rgba(0,0,0,0.5)${glow ? `, 0 0 70px ${glow}88` : ''}`,
      }}
    />
  );
};
