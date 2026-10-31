import React from 'react';
import {interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import {fonts} from './fonts';

/** "*word*," → {text: "word,", accent: true} */
const parseAccent = (word: string): {text: string; accent: boolean} => {
  const m = word.match(/^\*(.+)\*([^*]*)$/);
  return m ? {text: m[1] + m[2], accent: true} : {text: word.replace(/\*/g, ''), accent: false};
};

type KineticProps = {
  /** Supports *accent* syntax */
  text: string;
  size: number;
  color?: string;
  accent?: string;
  family?: string;
  weight?: number;
  delay?: number;
  /** pop: scale + rotate, rise: from below, slam: shrinks down from large and lands */
  animation?: 'pop' | 'rise' | 'slam';
  /** Delay per word (frames) */
  stagger?: number;
  /** Box behind each word (Reels caption style) */
  boxed?: string;
  align?: 'center' | 'left';
  lineHeight?: number;
  glow?: boolean;
};

/** Word-by-word animated headline. If you need uppercase, write the text in uppercase directly (for İ/Ş). */
export const Kinetic: React.FC<KineticProps> = ({
  text,
  size,
  color = '#fff',
  accent = '#facc15',
  family = fonts.display,
  weight = 400,
  delay = 0,
  animation = 'rise',
  stagger = 3,
  boxed,
  align = 'center',
  lineHeight = 1.02,
  glow = false,
}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const words = text.split(/\s+/).filter(Boolean);
  return (
    <div
      style={{
        display: 'flex',
        flexWrap: 'wrap',
        justifyContent: align === 'center' ? 'center' : 'flex-start',
        gap: `${size * 0.1}px ${size * 0.26}px`,
        fontFamily: family,
        fontWeight: weight,
        fontSize: size,
        lineHeight,
        color,
        textAlign: align,
      }}
    >
      {words.map((w, i) => {
        const s = spring({
          frame: frame - delay - i * stagger,
          fps,
          config: animation === 'rise' ? {damping: 200} : {damping: 12, stiffness: 190},
        });
        const transform =
          animation === 'pop'
            ? `scale(${interpolate(s, [0, 1], [0.3, 1])}) rotate(${interpolate(s, [0, 1], [-8, 0])}deg)`
            : animation === 'slam'
              ? `scale(${interpolate(s, [0, 1], [2.4, 1])})`
              : `translateY(${interpolate(s, [0, 1], [size * 0.6, 0])}px)`;
        const {text: clean, accent: isAccent} = parseAccent(w);
        return (
          <span
            key={i}
            style={{
              display: 'inline-block',
              opacity: Math.min(1, s * 1.4),
              transform,
              color: isAccent ? accent : color,
              padding: boxed ? `${size * 0.03}px ${size * 0.14}px` : 0,
              backgroundColor: boxed ?? 'transparent',
              borderRadius: boxed ? size * 0.12 : 0,
              textShadow: glow ? `0 0 ${size * 0.3}px ${isAccent ? accent : color}` : '0 6px 30px rgba(0,0,0,0.35)',
            }}
          >
            {clean}
          </span>
        );
      })}
    </div>
  );
};

/** Typewriter effect with a blinking cursor. */
export const Typewriter: React.FC<{
  text: string;
  size: number;
  color?: string;
  family?: string;
  delay?: number;
  /** Characters per second */
  speed?: number;
}> = ({text, size, color = '#fff', family = fonts.body, delay = 0, speed = 28}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const chars = [...text];
  const shown = Math.max(0, Math.min(chars.length, Math.floor(((frame - delay) / fps) * speed)));
  const cursor = Math.floor(frame / 15) % 2 === 0;
  return (
    <div style={{fontFamily: family, fontSize: size, color, fontWeight: 700, whiteSpace: 'pre-wrap'}}>
      {chars.slice(0, shown).join('')}
      <span style={{opacity: cursor ? 1 : 0}}>▍</span>
    </div>
  );
};

/** Caption / subtitle line in a translucent box, highlighted word by word. */
export const Caption: React.FC<{text: string; size?: number; accent?: string; delay?: number}> = ({
  text,
  size = 52,
  accent = '#facc15',
  delay = 0,
}) => (
  <div
    style={{
      backgroundColor: 'rgba(0,0,0,0.55)',
      borderRadius: size * 0.4,
      padding: `${size * 0.35}px ${size * 0.6}px`,
      backdropFilter: 'blur(12px)',
    }}
  >
    <Kinetic text={text} size={size} family={fonts.body} weight={800} accent={accent} delay={delay} stagger={2} lineHeight={1.15} />
  </div>
);
