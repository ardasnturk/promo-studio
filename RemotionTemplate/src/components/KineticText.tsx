import React from 'react';
import {interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';
import type {Brand} from '../types';
import type {ThemeStyle} from '../themes';

type Props = {
  text: string;
  brand: Brand;
  theme: ThemeStyle;
  size: number;
  delay?: number;
  color?: string;
  weight?: number;
  family?: string;
  uppercase?: boolean;
  highlight?: boolean;
};

const CJK_PUNCT = /^[、。！？!?,.，：:;；…）)」』]+/;

/**
 * Splits text in languages without spaces at natural breaks (punctuation, *accent*); punctuation stays with the preceding chunk.
 * Very long chunks are further split to at most `max` characters so they can still wrap.
 */
const segmentCJK = (text: string, max = 8): string[] => {
  const pieces: string[] = [];
  for (const m of text.match(/\*[^*]+\*|[^*]+/g) ?? []) {
    if (m.startsWith('*')) {
      pieces.push(m);
      continue;
    }
    for (const part of m.split(/(?<=[、。！？!?，,])/)) if (part) pieces.push(part);
  }
  const out: string[] = [];
  for (let piece of pieces) {
    const lead = piece.match(CJK_PUNCT);
    if (lead && out.length) {
      out[out.length - 1] += lead[0];
      piece = piece.slice(lead[0].length);
    }
    if (!piece) continue;
    if (piece.startsWith('*')) {
      out.push(piece);
      continue;
    }
    const chars = [...piece];
    for (let i = 0; i < chars.length; i += max) out.push(chars.slice(i, i + max).join(''));
  }
  return out;
};

/** Splits an accented chunk like "*word*," into (accent, trailing punctuation) */
const parseAccent = (word: string): {text: string; accent: boolean} => {
  const m = word.match(/^\*(.+)\*([^*]*)$/);
  return m ? {text: m[1] + m[2], accent: true} : {text: word.replace(/\*/g, ''), accent: false};
};

export const KineticText: React.FC<Props> = ({
  text,
  brand,
  theme,
  size,
  delay = 0,
  color = '#fff',
  weight,
  family,
  uppercase,
  highlight,
}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  // In languages without spaces (Japanese, Chinese), text is split into short chunks so lines can wrap.
  const spaced = text.split(/\s+/).filter(Boolean);
  const chunked = spaced.length === 1 && [...text].length > 7 && /[\u3040-\u30ff\u3400-\u9fff]/.test(text);
  const words = chunked ? segmentCJK(text) : spaced;
  const upper = uppercase ?? theme.uppercase;

  return (
    <div
      style={{
        display: 'flex',
        flexWrap: 'wrap',
        justifyContent: 'center',
        gap: `${size * 0.12}px ${chunked ? 0 : size * 0.28}px`,
        fontFamily: family ?? theme.fontFamily,
        fontWeight: weight ?? theme.titleWeight,
        fontSize: size,
        lineHeight: 1.08,
        color,
        textAlign: 'center',
        textTransform: upper ? 'uppercase' : 'none',
        letterSpacing: upper ? '-0.01em' : '-0.02em',
      }}
    >
      {words.map((word, i) => {
        const stagger = theme.textAnimation === 'words' ? 5 : 3;
        const s = spring({
          frame: frame - delay - i * stagger,
          fps,
          config: theme.textAnimation === 'pop' ? {damping: 11, stiffness: 180} : {damping: 200},
        });
        let transform = '';
        if (theme.textAnimation === 'pop') {
          transform = `scale(${interpolate(s, [0, 1], [0.3, 1])}) rotate(${interpolate(s, [0, 1], [-8, 0])}deg)`;
        } else {
          transform = `translateY(${interpolate(s, [0, 1], [size * 0.6, 0])}px)`;
        }
        // Accented word: *word* syntax is painted in the accent color
        const {text: clean, accent: isAccent} = parseAccent(word);
        return (
          <span
            key={i}
            style={{
              display: 'inline-block',
              opacity: s,
              transform,
              color: isAccent ? brand.accent : color,
              padding: highlight ? `${size * 0.04}px ${size * 0.16}px` : 0,
              backgroundColor: highlight ? (isAccent ? brand.primary : 'rgba(0,0,0,0.55)') : 'transparent',
              borderRadius: highlight ? size * 0.14 : 0,
              textShadow: theme.glow ? `0 0 ${size * 0.35}px ${isAccent ? brand.accent : brand.primary}` : 'none',
            }}
          >
            {clean}
          </span>
        );
      })}
    </div>
  );
};
