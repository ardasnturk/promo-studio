import React from 'react';
import {useCurrentFrame, useVideoConfig} from 'remotion';

export const ProgressBar: React.FC<{color: string}> = ({color}) => {
  const frame = useCurrentFrame();
  const {durationInFrames, width} = useVideoConfig();
  const progress = Math.min(1, frame / Math.max(1, durationInFrames - 1));
  return (
    <div
      style={{
        position: 'absolute',
        top: 60,
        left: 60,
        width: width - 120,
        height: 8,
        borderRadius: 8,
        backgroundColor: 'rgba(255,255,255,0.18)',
        overflow: 'hidden',
      }}
    >
      <div style={{width: `${progress * 100}%`, height: '100%', backgroundColor: color}} />
    </div>
  );
};
