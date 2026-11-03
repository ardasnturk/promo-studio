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

/** A real photo: `photo` as downloaded or uploaded, `cutout` the same photo with the background removed (PNG, when one was found). Paths relative to public/. */
export type StudioPhoto = {
  photo: string;
  cutout?: string;
};

export type StudioProps = {
  brand: StudioBrand;
  /** BCP-47 language code (needed for Turkish uppercasing) */
  lang: string;
  fps: number;
  durationInFrames: number;
  scenes: StudioScene[];
  /** Real logos (clubs, leagues, brands) from the storyboard: name → path relative to public/. Missing names have no image. */
  logos?: Record<string, string>;
  /** Real people (players, coaches…) from the storyboard: name → photo. Missing names have no photo. */
  people?: Record<string, StudioPhoto>;
  /** Images the user uploaded for this post: file name → photo */
  uploads?: Record<string, StudioPhoto>;
  /** Output size: 1080×1920 for videos; an image post can be 1080×1350 or 1080×1080 */
  width?: number;
  height?: number;
  /** `image`: a single picture; Promo Studio renders the last frame as the image */
  format?: 'video' | 'image';
};
