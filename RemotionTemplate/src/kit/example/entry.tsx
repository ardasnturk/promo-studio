import React from 'react';
import {Composition, registerRoot} from 'remotion';
import type {StudioProps} from '..';
import {ExampleVideo} from './ExampleVideo';

const scenes = ['Know the *score* first', 'AI *predictions*', 'Win *probability*', 'Goal! 2-1', '*Download* now'];
const defaultProps: StudioProps = {
  brand: {appName: 'Acme', primary: '#2563eb', accent: '#facc15', background: '#0b1220', storeLabel: 'Download on the App Store'},
  lang: 'en',
  fps: 30,
  durationInFrames: 75 * scenes.length,
  scenes: scenes.map((text, i) => ({from: i * 75, durationInFrames: 75, text, visual: '', assets: []})),
};

const Root: React.FC = () => (
  <Composition
    id="KitExample"
    component={ExampleVideo as unknown as React.FC<Record<string, unknown>>}
    width={1080}
    height={1920}
    fps={30}
    durationInFrames={defaultProps.durationInFrames}
    defaultProps={defaultProps as unknown as Record<string, unknown>}
    calculateMetadata={({props}) => {
      const p = props as unknown as StudioProps;
      return {fps: p.fps, durationInFrames: p.durationInFrames};
    }}
  />
);

registerRoot(Root);
