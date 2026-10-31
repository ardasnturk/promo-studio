import React from 'react';
import {Composition} from 'remotion';
import {AppPromo, TRANSITION_FRAMES, sceneFrames} from './AppPromo';
import type {VideoSpec} from './types';

const defaultProps: VideoSpec = {
  theme: 'hype',
  brand: {appName: 'Acme', primary: '#16a34a', accent: '#facc15', background: '#0b1220'},
  scenes: [
    {kind: 'hook', title: 'Know the *score* first', subtitle: 'AI match predictions', emoji: '⚽'},
    {kind: 'feature', title: "What's inside?", bullets: ['AI predictions', 'Live scores', 'Manager mode']},
    {kind: 'stat', title: 'prediction accuracy', stat: '78%'},
    {kind: 'cta', title: 'Try it *now*', subtitle: 'Free'},
  ],
};

export const RemotionRoot: React.FC = () => {
  return (
    <Composition
      id="AppPromo"
      component={AppPromo as unknown as React.FC<Record<string, unknown>>}
      width={1080}
      height={1920}
      fps={30}
      durationInFrames={300}
      defaultProps={defaultProps as unknown as Record<string, unknown>}
      calculateMetadata={({props}) => {
        const spec = props as unknown as VideoSpec;
        const fps = spec.fps ?? 30;
        const total = spec.scenes.reduce((sum, s) => sum + sceneFrames(s.durationSec, fps), 0);
        return {
          fps,
          durationInFrames: Math.max(30, total - TRANSITION_FRAMES * Math.max(0, spec.scenes.length - 1)),
        };
      }}
    />
  );
};
