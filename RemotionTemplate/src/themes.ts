import {loadFont as loadMontserrat} from '@remotion/google-fonts/Montserrat';
import {loadFont as loadInter} from '@remotion/google-fonts/Inter';
import {loadFont as loadSpaceGrotesk} from '@remotion/google-fonts/SpaceGrotesk';
import {loadFont as loadNotoJP} from '@remotion/google-fonts/NotoSansJP';
import {loadFont as loadNotoSC} from '@remotion/google-fonts/NotoSansSC';
import type {ThemeId} from './types';

const subsets: ('latin' | 'latin-ext')[] = ['latin', 'latin-ext'];
const montserrat = loadMontserrat('normal', {weights: ['700', '900'], subsets});
const inter = loadInter('normal', {weights: ['500', '800'], subsets});
const space = loadSpaceGrotesk('normal', {weights: ['500', '700'], subsets});

export type ThemeStyle = {
  fontFamily: string;
  bodyFamily: string;
  titleWeight: number;
  uppercase: boolean;
  background: 'blobs' | 'gradient' | 'grid' | 'solid';
  transition: 'slide' | 'fade' | 'wipe';
  textAnimation: 'pop' | 'rise' | 'words';
  /** Highlight box behind headlines (TikTok/Reels caption style) */
  highlightBox: boolean;
  glow: boolean;
};

// CJK fonts are large, so they are loaded only when rendering a video in that language.
const cjkCache: Record<string, string> = {};
const cjkFamily = (lang: string): string | null => {
  if (lang.startsWith('ja')) {
    cjkCache.ja ??= loadNotoJP('normal', {weights: ['500', '800'], subsets: ['japanese', 'latin']}).fontFamily;
    return cjkCache.ja;
  }
  if (lang.startsWith('zh')) {
    cjkCache.zh ??= loadNotoSC('normal', {weights: ['500', '800'], subsets: ['chinese-simplified', 'latin']}).fontFamily;
    return cjkCache.zh;
  }
  return null;
};

export const isCJK = (lang?: string) => !!lang && (lang.startsWith('ja') || lang.startsWith('zh'));

/** Per-language theme: CJK languages use the Noto font and disable uppercasing. */
export const themeFor = (id: ThemeId, lang?: string): ThemeStyle => {
  const base = THEMES[id] ?? THEMES.hype;
  const family = lang ? cjkFamily(lang) : null;
  if (!family) return base;
  return {...base, fontFamily: family, bodyFamily: family, titleWeight: 800, uppercase: false};
};

export const THEMES: Record<ThemeId, ThemeStyle> = {
  hype: {
    fontFamily: montserrat.fontFamily,
    bodyFamily: inter.fontFamily,
    titleWeight: 900,
    uppercase: true,
    background: 'blobs',
    transition: 'slide',
    textAnimation: 'pop',
    highlightBox: true,
    glow: false,
  },
  showcase: {
    fontFamily: inter.fontFamily,
    bodyFamily: inter.fontFamily,
    titleWeight: 800,
    uppercase: false,
    background: 'gradient',
    transition: 'fade',
    textAnimation: 'rise',
    highlightBox: false,
    glow: false,
  },
  neon: {
    fontFamily: space.fontFamily,
    bodyFamily: space.fontFamily,
    titleWeight: 700,
    uppercase: true,
    background: 'grid',
    transition: 'wipe',
    textAnimation: 'pop',
    highlightBox: false,
    glow: true,
  },
  minimal: {
    fontFamily: inter.fontFamily,
    bodyFamily: inter.fontFamily,
    titleWeight: 800,
    uppercase: false,
    background: 'solid',
    transition: 'fade',
    textAnimation: 'words',
    highlightBox: false,
    glow: false,
  },
};
