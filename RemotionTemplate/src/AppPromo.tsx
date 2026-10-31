import React from 'react';
import {AbsoluteFill, Audio, interpolate, staticFile, useVideoConfig} from 'remotion';
import {TransitionSeries, linearTiming} from '@remotion/transitions';
import type {TransitionPresentation} from '@remotion/transitions';
import {fade} from '@remotion/transitions/fade';
import {slide} from '@remotion/transitions/slide';
import {wipe} from '@remotion/transitions/wipe';
import {Background} from './components/Background';
import {ProgressBar} from './components/ProgressBar';
import {SCENE_COMPONENTS} from './scenes/Scenes';
import {themeFor} from './themes';
import type {VideoSpec} from './types';

export const TRANSITION_FRAMES = 12;
export const DEFAULT_SCENE_SEC = 3;

export const sceneFrames = (sec: number | undefined, fps: number) =>
  Math.max(TRANSITION_FRAMES + 15, Math.round((sec ?? DEFAULT_SCENE_SEC) * fps));

export const AppPromo: React.FC<VideoSpec> = (spec) => {
  const {fps, durationInFrames} = useVideoConfig();
  const theme = themeFor(spec.theme, spec.lang);
  // With a voiceover, music is ducked enough to sit under the speech
  const musicLevel = spec.scenes.some((s) => s.audio) ? 0.16 : 0.6;

  // Widened to a common type because the transitions' prop types don't match.
  const presentation = (i: number): TransitionPresentation<Record<string, unknown>> => {
    if (theme.transition === 'slide')
      return slide({direction: i % 2 ? 'from-left' : 'from-right'}) as TransitionPresentation<Record<string, unknown>>;
    if (theme.transition === 'wipe')
      return wipe({direction: 'from-bottom'}) as TransitionPresentation<Record<string, unknown>>;
    return fade() as TransitionPresentation<Record<string, unknown>>;
  };

  return (
    <AbsoluteFill lang={spec.lang ?? 'tr'} style={{backgroundColor: spec.brand.background}}>
      <Background brand={spec.brand} theme={theme} />
      <TransitionSeries>
        {spec.scenes.flatMap((scene, i) => {
          const Comp = SCENE_COMPONENTS[scene.kind] ?? SCENE_COMPONENTS.hook;
          const items = [
            <TransitionSeries.Sequence key={`s${i}`} durationInFrames={sceneFrames(scene.durationSec, fps)}>
              <Comp scene={scene} brand={spec.brand} theme={theme} />
              {scene.audio ? <Audio src={staticFile(scene.audio)} /> : null}
            </TransitionSeries.Sequence>,
          ];
          if (i < spec.scenes.length - 1) {
            items.push(
              <TransitionSeries.Transition
                key={`t${i}`}
                presentation={presentation(i)}
                timing={linearTiming({durationInFrames: TRANSITION_FRAMES})}
              />,
            );
          }
          return items;
        })}
      </TransitionSeries>
      <ProgressBar color={spec.brand.accent} />
      {spec.music ? (
        <Audio
          src={staticFile(spec.music)}
          volume={(f) =>
            interpolate(f, [0, 15, durationInFrames - 30, durationInFrames], [0, musicLevel, musicLevel, 0], {
              extrapolateLeft: 'clamp',
              extrapolateRight: 'clamp',
            })
          }
        />
      ) : null}
    </AbsoluteFill>
  );
};
