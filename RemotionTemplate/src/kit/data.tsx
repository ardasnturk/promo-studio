import React from 'react';
import {interpolate, useCurrentFrame} from 'remotion';
import {fonts} from './fonts';
import {useEnter, useProgress} from './motion';

/** Counts from `from` to `to`. Formatted with `decimals`, `prefix`, `suffix`. */
export const Counter: React.FC<{
  to: number;
  from?: number;
  start?: number;
  end?: number;
  size: number;
  color?: string;
  decimals?: number;
  prefix?: string;
  suffix?: string;
  family?: string;
  /** Locale for the thousands separator (e.g. 'en') */
  locale?: string;
}> = ({to, from = 0, start = 0, end = 40, size, color = '#fff', decimals = 0, prefix = '', suffix = '', family = fonts.display, locale = 'tr'}) => {
  const t = useProgress(start, end);
  const value = from + (to - from) * t;
  const text = value.toLocaleString(locale, {minimumFractionDigits: decimals, maximumFractionDigits: decimals});
  return (
    <div style={{fontFamily: family, fontSize: size, color, lineHeight: 1, fontVariantNumeric: 'tabular-nums'}}>
      {prefix}
      {text}
      {suffix}
    </div>
  );
};

/**
 * Three-part probability bar (e.g. win / draw / loss).
 * values must sum to 100. Segments fill in order and the percentages count up.
 */
export const ProbabilityBar: React.FC<{
  values: number[];
  colors: string[];
  labels: string[];
  width: number;
  height?: number;
  start?: number;
}> = ({values, colors, labels, width, height = 64, start = 0}) => {
  const t = useProgress(start, start + 40);
  return (
    <div style={{width}}>
      <div style={{display: 'flex', width, height, borderRadius: height / 2, overflow: 'hidden', backgroundColor: 'rgba(255,255,255,0.12)'}}>
        {values.map((v, i) => (
          <div key={i} style={{width: `${v * t}%`, backgroundColor: colors[i % colors.length]}} />
        ))}
      </div>
      <div style={{display: 'flex', justifyContent: 'space-between', marginTop: 18, fontFamily: fonts.body, fontWeight: 800, fontSize: height * 0.6, color: '#fff'}}>
        {values.map((v, i) => (
          <div key={i} style={{textAlign: i === 0 ? 'left' : i === values.length - 1 ? 'right' : 'center', flex: 1}}>
            <div style={{color: colors[i % colors.length]}}>%{Math.round(v * t)}</div>
            <div style={{fontSize: height * 0.4, opacity: 0.8, fontWeight: 600}}>{labels[i]}</div>
          </div>
        ))}
      </div>
    </div>
  );
};

/** Horizontal bar chart; bars fill in order. */
export const BarChart: React.FC<{
  items: {label: string; value: number}[];
  width: number;
  color: string;
  max?: number;
  start?: number;
  suffix?: string;
}> = ({items, width, color, max, start = 0, suffix = ''}) => {
  const top = max ?? Math.max(...items.map((i) => i.value), 1);
  return (
    <div style={{width, display: 'flex', flexDirection: 'column', gap: 26}}>
      {items.map((item, i) => (
        <Bar key={i} item={item} width={width} color={color} top={top} start={start + i * 6} suffix={suffix} />
      ))}
    </div>
  );
};

const Bar: React.FC<{item: {label: string; value: number}; width: number; color: string; top: number; start: number; suffix: string}> = ({
  item,
  width,
  color,
  top,
  start,
  suffix,
}) => {
  const t = useProgress(start, start + 30);
  return (
    <div style={{fontFamily: fonts.body, color: '#fff'}}>
      <div style={{display: 'flex', justifyContent: 'space-between', fontSize: 40, fontWeight: 700, marginBottom: 10}}>
        <span>{item.label}</span>
        <span>
          {Math.round(item.value * t)}
          {suffix}
        </span>
      </div>
      <div style={{height: 30, borderRadius: 15, backgroundColor: 'rgba(255,255,255,0.12)'}}>
        <div style={{height: '100%', width: (width * item.value * t) / top, borderRadius: 15, backgroundColor: color}} />
      </div>
    </div>
  );
};

/** Countdown clock (e.g. time until kickoff). `seconds` is the start value and decreases with video time. */
export const Countdown: React.FC<{seconds: number; size: number; color?: string; fps?: number}> = ({seconds, size, color = '#fff', fps = 30}) => {
  const frame = useCurrentFrame();
  const left = Math.max(0, seconds - Math.floor(frame / fps));
  const h = Math.floor(left / 3600);
  const m = Math.floor((left % 3600) / 60);
  const s = left % 60;
  const pad = (n: number) => String(n).padStart(2, '0');
  return (
    <div style={{fontFamily: fonts.mono, fontWeight: 700, fontSize: size, color, letterSpacing: '0.04em', fontVariantNumeric: 'tabular-nums'}}>
      {pad(h)}:{pad(m)}:{pad(s)}
    </div>
  );
};

/** Team / brand badge drawn from colors and an abbreviation (instead of an official logo). */
export const Badge: React.FC<{code: string; primary: string; secondary: string; size: number; delay?: number}> = ({
  code,
  primary,
  secondary,
  size,
  delay = 0,
}) => {
  const s = useEnter(delay, true);
  return (
    <div
      style={{
        width: size,
        height: size * 1.15,
        clipPath: 'polygon(50% 0, 100% 14%, 100% 62%, 50% 100%, 0 62%, 0 14%)',
        background: `linear-gradient(160deg, ${primary} 0%, ${primary} 55%, ${secondary} 55%, ${secondary} 100%)`,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        fontFamily: fonts.display,
        fontSize: size * 0.34,
        color: '#fff',
        textShadow: '0 4px 14px rgba(0,0,0,0.5)',
        transform: `scale(${s})`,
      }}
    >
      {code}
    </div>
  );
};

/** Two-sided score / matchup board. */
export const Matchup: React.FC<{
  home: {code: string; name: string; primary: string; secondary: string};
  away: {code: string; name: string; primary: string; secondary: string};
  center?: string;
  width: number;
  delay?: number;
}> = ({home, away, center = 'VS', width, delay = 0}) => {
  const s = useEnter(delay + 8, true);
  const side = (t: typeof home, d: number) => (
    <div style={{display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 18, width: width * 0.36}}>
      <Badge code={t.code} primary={t.primary} secondary={t.secondary} size={width * 0.26} delay={d} />
      <div style={{fontFamily: fonts.heading, fontWeight: 900, fontSize: width * 0.05, color: '#fff', textAlign: 'center'}}>{t.name}</div>
    </div>
  );
  return (
    <div style={{width, display: 'flex', alignItems: 'center', justifyContent: 'space-between'}}>
      {side(home, delay)}
      <div style={{fontFamily: fonts.display, fontSize: width * 0.11, color: '#fff', transform: `scale(${interpolate(s, [0, 1], [2, 1])})`, opacity: s}}>{center}</div>
      {side(away, delay + 4)}
    </div>
  );
};
