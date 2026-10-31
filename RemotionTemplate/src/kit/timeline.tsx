import React from 'react';
import {AbsoluteFill, Audio, Sequence, interpolate, staticFile, useCurrentFrame} from 'remotion';
import type {StudioScene} from './types';

/**
 * Sequences storyboard scenes using the timing in props and plays each scene's voiceover.
 * `render(i, scene)` returns the scene's visuals; inside it, useCurrentFrame() counts from the scene start.
 * `overlap`: crossfade frames between scenes (0 = hard cut).
 */
export const Timeline: React.FC<{
  scenes: StudioScene[];
  render: (index: number, scene: StudioScene) => React.ReactNode;
  overlap?: number;
}> = ({scenes, render, overlap = 0}) => (
  <>
    {scenes.map((scene, i) => (
      <Sequence key={i} from={scene.from} durationInFrames={scene.durationInFrames + (i < scenes.length - 1 ? overlap : 0)} name={`Sahne ${i + 1}`}>
        <SceneFade duration={scene.durationInFrames + (i < scenes.length - 1 ? overlap : 0)} fadeIn={i > 0 ? overlap : 0} fadeOut={i < scenes.length - 1 ? overlap : 0}>
          {render(i, scene)}
        </SceneFade>
        {scene.audio ? <Audio src={staticFile(scene.audio)} /> : null}
      </Sequence>
    ))}
  </>
);

const SceneFade: React.FC<{duration: number; fadeIn: number; fadeOut: number; children: React.ReactNode}> = ({duration, fadeIn, fadeOut, children}) => {
  const frame = useCurrentFrame();
  const a = fadeIn > 0 ? interpolate(frame, [0, fadeIn], [0, 1], {extrapolateRight: 'clamp'}) : 1;
  const b = fadeOut > 0 ? interpolate(frame, [duration - fadeOut, duration], [1, 0], {extrapolateLeft: 'clamp'}) : 1;
  return <AbsoluteFill style={{opacity: Math.min(a, b)}}>{children}</AbsoluteFill>;
};

/** Royalty-free sound effects (remotion.media). Use only sounds from this list. */
export const SFX = {
  whoosh: 'https://remotion.media/whoosh.wav',
  whip: 'https://remotion.media/whip.wav',
  switch: 'https://remotion.media/switch.wav',
  ding: 'https://remotion.media/ding.wav',
  click: 'https://remotion.media/mouse-click.wav',
  pageTurn: 'https://remotion.media/page-turn.wav',
  shutter: 'https://remotion.media/shutter-modern.wav',
  notification: 'https://remotion.media/snapchat-notification.wav',
  boom: 'https://remotion.media/vine-boom.wav',
  dramatic: 'https://remotion.media/dramatic-boomer.wav',
  recordScratch: 'https://remotion.media/record-scratch.wav',
  yippee: 'https://remotion.media/yippee.wav',
  wow: 'https://remotion.media/anime-wow.wav',
} as const;

/** Plays a sound effect at frame `at` (relative to its Sequence). Default volume is low so it doesn't drown out the voiceover. */
export const Sfx: React.FC<{sound: keyof typeof SFX; at?: number; volume?: number}> = ({sound, at = 0, volume = 0.45}) => (
  <Sequence from={at} durationInFrames={90} layout="none">
    <Audio src={SFX[sound]} volume={volume} />
  </Sequence>
);
