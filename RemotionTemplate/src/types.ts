// Must stay in sync with the Swift `VideoSpec` (PromoStudio/Models/VideoSpec.swift).
export type ThemeId = 'hype' | 'showcase' | 'neon' | 'minimal';

export type SceneKind = 'hook' | 'screenshot' | 'feature' | 'stat' | 'cta';

export type Scene = {
  kind: SceneKind;
  title: string;
  subtitle?: string;
  /** Path relative to public/ */
  image?: string;
  /** 'phone' = inside a phone frame, 'raw' = image is already framed (store screenshot etc.) */
  imageStyle?: 'phone' | 'raw';
  bullets?: string[];
  stat?: string;
  emoji?: string;
  durationSec?: number;
  /** Voiceover text (not used in the render, informational only) */
  voiceover?: string;
  /** Scene voiceover file, relative to public/ */
  audio?: string;
};

export type Brand = {
  appName: string;
  primary: string;
  accent: string;
  background: string;
  logo?: string;
  storeLabel?: string;
};

export type VideoSpec = {
  theme: ThemeId;
  brand: Brand;
  scenes: Scene[];
  music?: string;
  fps?: number;
  /** BCP-47 language code; needed for uppercasing (e.g. Turkish İ) */
  lang?: string;
};
