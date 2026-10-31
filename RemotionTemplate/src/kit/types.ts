// Props the Promo Studio studio passes to every custom video. Swift side: PromoStudio/Services/StudioService.swift (StudioProps).

export type StudioBrand = {
  appName: string;
  primary: string;
  accent: string;
  background: string;
  /** Logo path relative to public/ */
  logo?: string;
  /** Store label such as "Download on the App Store" (in the video's language) */
  storeLabel?: string;
};

export type StudioScene = {
  /** Frame at which the scene starts, counted from the start of the video */
  from: number;
  /** Scene duration in frames (adjusted to the audio length when there is a voiceover) */
  durationInFrames: number;
  /** On-screen text from the storyboard (may use *accent* syntax) */
  text: string;
  /** Visual director's note from the storyboard */
  visual: string;
  /** Voiceover file relative to public/ */
  audio?: string;
  /** Project images to use in the scene (paths relative to public/) */
  assets: string[];
};

export type StudioProps = {
  brand: StudioBrand;
  /** BCP-47 language code (needed for Turkish uppercasing) */
  lang: string;
  fps: number;
  durationInFrames: number;
  scenes: StudioScene[];
};
