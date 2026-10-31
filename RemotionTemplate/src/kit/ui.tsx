import React from 'react';
import {Img, interpolate, staticFile, useCurrentFrame} from 'remotion';
import {fonts} from './fonts';
import {useEnter} from './motion';

/** Generic notification card (like a lock screen notification). Not an exact copy of any specific OS UI. */
export const Notification: React.FC<{
  title: string;
  body: string;
  /** Icon path relative to public/ */
  icon?: string;
  time?: string;
  width: number;
  delay?: number;
  accent?: string;
}> = ({title, body, icon, time = 'now', width, delay = 0, accent = '#fff'}) => {
  const s = useEnter(delay, true);
  return (
    <div
      style={{
        width,
        display: 'flex',
        gap: 26,
        alignItems: 'center',
        padding: '30px 34px',
        borderRadius: 44,
        backgroundColor: 'rgba(30,30,34,0.78)',
        backdropFilter: 'blur(24px)',
        boxShadow: '0 30px 80px rgba(0,0,0,0.45)',
        border: '1px solid rgba(255,255,255,0.12)',
        transform: `translateY(${interpolate(s, [0, 1], [-180, 0])}px) scale(${interpolate(s, [0, 1], [0.9, 1])})`,
        opacity: s,
        fontFamily: fonts.body,
        color: '#fff',
      }}
    >
      {icon ? <Img src={staticFile(icon)} style={{width: 96, height: 96, borderRadius: 22}} /> : <div style={{width: 96, height: 96, borderRadius: 22, backgroundColor: accent}} />}
      <div style={{flex: 1, minWidth: 0}}>
        <div style={{display: 'flex', justifyContent: 'space-between', fontSize: 34, fontWeight: 800}}>
          <span>{title}</span>
          <span style={{fontWeight: 500, opacity: 0.6, fontSize: 28}}>{time}</span>
        </div>
        <div style={{fontSize: 34, fontWeight: 500, opacity: 0.9, marginTop: 6}}>{body}</div>
      </div>
    </div>
  );
};

/** Pill-shaped label (e.g. "LIVE", "NEW", "PRO"). `pulse` makes it pulse like a live broadcast. */
export const Chip: React.FC<{label: string; color: string; textColor?: string; size?: number; pulse?: boolean; delay?: number}> = ({
  label,
  color,
  textColor = '#fff',
  size = 40,
  pulse = false,
  delay = 0,
}) => {
  const frame = useCurrentFrame();
  const s = useEnter(delay, true);
  const dot = pulse ? 0.4 + 0.6 * Math.abs(((frame % 30) - 15) / 15) : 1;
  return (
    <div
      style={{
        display: 'inline-flex',
        alignItems: 'center',
        gap: size * 0.35,
        padding: `${size * 0.3}px ${size * 0.6}px`,
        borderRadius: size,
        backgroundColor: color,
        color: textColor,
        fontFamily: fonts.body,
        fontWeight: 800,
        fontSize: size,
        letterSpacing: '0.04em',
        transform: `scale(${s})`,
      }}
    >
      {pulse ? <span style={{width: size * 0.4, height: size * 0.4, borderRadius: size, backgroundColor: textColor, opacity: dot}} /> : null}
      {label}
    </div>
  );
};

/** Glass-effect card: put any content inside. */
export const GlassCard: React.FC<{width: number; children: React.ReactNode; delay?: number; glow?: string; padding?: number}> = ({
  width,
  children,
  delay = 0,
  glow,
  padding = 48,
}) => {
  const s = useEnter(delay);
  return (
    <div
      style={{
        width,
        padding,
        borderRadius: 48,
        backgroundColor: 'rgba(255,255,255,0.08)',
        border: '1px solid rgba(255,255,255,0.16)',
        backdropFilter: 'blur(20px)',
        boxShadow: `0 30px 90px rgba(0,0,0,0.4)${glow ? `, 0 0 80px ${glow}44` : ''}`,
        opacity: s,
        transform: `translateY(${interpolate(s, [0, 1], [80, 0])}px)`,
      }}
    >
      {children}
    </div>
  );
};

/** Continuously scrolling text band (news ticker). */
export const Ticker: React.FC<{items: string[]; color: string; textColor?: string; speed?: number; height?: number}> = ({
  items,
  color,
  textColor = '#fff',
  speed = 6,
  height = 90,
}) => {
  const frame = useCurrentFrame();
  const text = items.join('   •   ');
  return (
    <div style={{height, backgroundColor: color, overflow: 'hidden', display: 'flex', alignItems: 'center', width: '100%'}}>
      <div
        style={{
          whiteSpace: 'nowrap',
          fontFamily: fonts.condensed,
          fontSize: height * 0.6,
          color: textColor,
          transform: `translateX(${-((frame * speed) % 2400)}px)`,
        }}
      >
        {`${text}   •   ${text}   •   ${text}`}
      </div>
    </div>
  );
};

/** Simple list: items slide in from the left one by one, each with a marker. */
export const StaggerList: React.FC<{items: string[]; size?: number; color?: string; marker?: string; delay?: number}> = ({
  items,
  size = 52,
  color = '#fff',
  marker = '#facc15',
  delay = 0,
}) => (
  <div style={{display: 'flex', flexDirection: 'column', gap: size * 0.55}}>
    {items.map((it, i) => (
      <ListItem key={i} text={it} size={size} color={color} marker={marker} delay={delay + i * 7} />
    ))}
  </div>
);

const ListItem: React.FC<{text: string; size: number; color: string; marker: string; delay: number}> = ({text, size, color, marker, delay}) => {
  const s = useEnter(delay);
  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: size * 0.5,
        fontFamily: fonts.body,
        fontWeight: 800,
        fontSize: size,
        color,
        opacity: s,
        transform: `translateX(${interpolate(s, [0, 1], [-120, 0])}px)`,
      }}
    >
      <span style={{width: size * 0.42, height: size * 0.42, borderRadius: size, backgroundColor: marker, flexShrink: 0}} />
      {text}
    </div>
  );
};
