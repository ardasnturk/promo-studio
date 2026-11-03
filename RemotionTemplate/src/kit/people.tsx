import React from 'react';
import {AbsoluteFill, Img, interpolate, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {fonts} from './fonts';
import {useEnter} from './motion';
import type {StudioPhoto} from './types';

/**
 * Looks for a real person photo. All of them are color and filter treatments of the same photo;
 * the person's pose and expression stay as photographed.
 * - `fierce`: hard contrast, a burning rim light in `color`, dark lower fade (intense, competitive)
 * - `heroic`: warm and bright, soft glow (celebration, hero shot)
 * - `mono`: black and white with a `color` duotone (poster, dramatic)
 * - `natural`: the photo as it is, only a soft shadow
 */
export type PortraitMood = 'fierce' | 'heroic' | 'mono' | 'natural';

const filters: Record<PortraitMood, string> = {
  fierce: 'contrast(1.35) saturate(1.15) brightness(0.92)',
  heroic: 'contrast(1.1) saturate(1.2) brightness(1.08) sepia(0.12)',
  mono: 'grayscale(1) contrast(1.45) brightness(0.95)',
  natural: 'none',
};

/**
 * A real person from `props.people`: the cut-out (background removed) when there is one, else the photo in a card.
 * `flip` mirrors them (to make two people face each other). `height` is the height of the person;
 * `width` (optional) is the box they are fitted into, anchored at the bottom center.
 */
export const Portrait: React.FC<{
  person: StudioPhoto;
  height: number;
  width?: number;
  mood?: PortraitMood;
  /** Rim light / duotone color, e.g. the team color */
  color?: string;
  flip?: boolean;
  delay?: number;
  /** Slide in from this side (default: rise from below) */
  from?: 'left' | 'right' | 'bottom';
}> = ({person, height, width, mood = 'fierce', color = '#ff2d2d', flip = false, delay = 0, from = 'bottom'}) => {
  const frame = useCurrentFrame();
  const enter = useEnter(delay);
  const push = interpolate(frame - delay, [0, 240], [1, 1.06], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  const offset = interpolate(enter, [0, 1], [1, 0]);
  const slide = from === 'left' ? `translateX(${-offset * height * 0.6}px)` : from === 'right' ? `translateX(${offset * height * 0.6}px)` : `translateY(${offset * height * 0.25}px)`;
  const src = staticFile(person.cutout ?? person.photo);
  const cut = Boolean(person.cutout);
  const rim =
    mood === 'fierce' ? `drop-shadow(0 0 2px ${color}) drop-shadow(0 0 18px ${color}cc) drop-shadow(0 0 60px ${color}66)`
    : mood === 'heroic' ? 'drop-shadow(0 0 30px rgba(255,220,150,0.55))'
    : 'drop-shadow(0 24px 40px rgba(0,0,0,0.55))';

  const boxWidth = width ?? (cut ? undefined : height * 0.78);
  const image = (
    <Img
      src={src}
      style={{
        height,
        width: boxWidth ?? 'auto',
        objectFit: cut ? 'contain' : 'cover',
        objectPosition: cut ? 'center bottom' : 'center top',
        filter: `${filters[mood]} ${cut ? rim : ''}`.trim(),
        display: 'block',
      }}
    />
  );
  // The overlays only cover the person: masked with the cut-out, fitted the same way as the image
  const mask = cut ? {WebkitMaskImage: `url(${src})`, WebkitMaskSize: 'contain', WebkitMaskPosition: 'center bottom', WebkitMaskRepeat: 'no-repeat'} : {};
  return (
    <div style={{position: 'relative', opacity: enter, transform: `${slide} scale(${push}) scaleX(${flip ? -1 : 1})`, transformOrigin: 'bottom center'}}>
      {cut ? (
        image
      ) : (
        <div style={{borderRadius: height * 0.04, overflow: 'hidden', boxShadow: `0 30px 80px rgba(0,0,0,0.6), 0 0 0 4px ${color}`}}>{image}</div>
      )}
      {mood === 'mono' && (
        // Duotone: the color laid over the photo, only where the person is
        <div
          style={{
            position: 'absolute', inset: 0, background: color, mixBlendMode: 'color', opacity: 0.85, borderRadius: cut ? 0 : height * 0.04, ...mask,
          }}
        />
      )}
      {mood === 'fierce' && (
        <div
          style={{
            position: 'absolute', inset: 0, background: `linear-gradient(to top, ${color}aa, transparent 45%)`, mixBlendMode: 'multiply', borderRadius: cut ? 0 : height * 0.04, ...mask,
          }}
        />
      )}
    </div>
  );
};

/**
 * Two people face to face: split background in their colors, both slide in toward the middle and a center word slams in.
 * They are mirrored to face each other (`flipLeft`/`flipRight` override it if a photo already faces inward).
 */
export const FaceOff: React.FC<{
  left: {person: StudioPhoto; name?: string; color: string};
  right: {person: StudioPhoto; name?: string; color: string};
  center?: string;
  mood?: PortraitMood;
  flipLeft?: boolean;
  flipRight?: boolean;
  delay?: number;
}> = ({left, right, center = 'VS', mood = 'fierce', flipLeft = false, flipRight = true, delay = 0}) => {
  const frame = useCurrentFrame();
  const {width, height} = useVideoConfig();
  const slam = useEnter(delay + 14, true);
  const flash = interpolate(frame - delay - 14, [0, 3, 10], [0, 0.7, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  const split = interpolate(useEnter(delay), [0, 1], [0, 1]);
  const label = (name: string | undefined, color: string, align: 'left' | 'right') =>
    name ? (
      <div style={{position: 'absolute', bottom: height * 0.08, [align]: 70, fontFamily: fonts.display, fontSize: 92, color: '#fff', textShadow: `0 0 30px ${color}`, opacity: slam}}>{name}</div>
    ) : null;
  return (
    <AbsoluteFill style={{overflow: 'hidden'}}>
      <AbsoluteFill style={{background: `linear-gradient(115deg, ${left.color} 0%, ${left.color}55 ${48 * split}%, ${right.color}55 ${100 - 48 * split}%, ${right.color} 100%)`}} />
      <AbsoluteFill style={{background: 'radial-gradient(circle at 50% 45%, transparent 0%, rgba(0,0,0,0.75) 75%)'}} />
      {/* Each person fills their own half, overlapping a little in the middle */}
      <div style={{position: 'absolute', left: -30, bottom: 0}}>
        <Portrait person={left.person} width={width * 0.6} height={height * 0.68} mood={mood} color={left.color} flip={flipLeft} from="left" delay={delay} />
      </div>
      <div style={{position: 'absolute', right: -30, bottom: 0}}>
        <Portrait person={right.person} width={width * 0.6} height={height * 0.68} mood={mood} color={right.color} flip={flipRight} from="right" delay={delay + 4} />
      </div>
      {label(left.name, left.color, 'left')}
      {label(right.name, right.color, 'right')}
      <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', paddingBottom: height * 0.12}}>
        <div
          style={{
            fontFamily: fonts.display, fontSize: 260, color: '#fff', opacity: slam,
            transform: `scale(${interpolate(slam, [0, 1], [3, 1])}) rotate(-6deg)`,
            textShadow: '0 0 40px rgba(255,255,255,0.8), 0 12px 40px rgba(0,0,0,0.8)',
          }}
        >
          {center}
        </div>
      </AbsoluteFill>
      <AbsoluteFill style={{background: '#fff', opacity: flash}} />
    </AbsoluteFill>
  );
};
