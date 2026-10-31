import {loadFont as loadAnton} from '@remotion/google-fonts/Anton';
import {loadFont as loadBebas} from '@remotion/google-fonts/BebasNeue';
import {loadFont as loadMontserrat} from '@remotion/google-fonts/Montserrat';
import {loadFont as loadInter} from '@remotion/google-fonts/Inter';
import {loadFont as loadSpaceGrotesk} from '@remotion/google-fonts/SpaceGrotesk';

const subsets: ('latin' | 'latin-ext')[] = ['latin', 'latin-ext'];

/** The kit's font families. All support extended Latin characters (latin-ext). */
export const fonts = {
  /** Condensed, extra-bold headline font (sports, hype) */
  display: loadAnton('normal', {weights: ['400'], subsets}).fontFamily,
  /** Condensed headline, calmer */
  condensed: loadBebas('normal', {weights: ['400'], subsets}).fontFamily,
  /** Bold heading */
  heading: loadMontserrat('normal', {weights: ['700', '900'], subsets}).fontFamily,
  /** Body text and UI */
  body: loadInter('normal', {weights: ['500', '700', '800'], subsets}).fontFamily,
  /** Technical / modern accent, numbers */
  mono: loadSpaceGrotesk('normal', {weights: ['500', '700'], subsets}).fontFamily,
};
