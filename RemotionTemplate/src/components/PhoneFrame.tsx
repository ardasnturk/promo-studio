import React from 'react';
import {Img, staticFile} from 'remotion';

export const PhoneFrame: React.FC<{src: string; width: number; style?: 'phone' | 'raw'; glow?: string}> = ({
  src,
  width,
  style = 'phone',
  glow,
}) => {
  if (style === 'raw') {
    return (
      <Img
        src={staticFile(src)}
        style={{
          width,
          borderRadius: width * 0.06,
          boxShadow: `0 40px 120px rgba(0,0,0,0.55)${glow ? `, 0 0 80px ${glow}66` : ''}`,
        }}
      />
    );
  }
  const height = width * 2.165;
  const bezel = width * 0.035;
  return (
    <div
      style={{
        width,
        height,
        borderRadius: width * 0.16,
        padding: bezel,
        background: 'linear-gradient(145deg, #2b2b30, #0c0c0e)',
        boxShadow: `0 50px 140px rgba(0,0,0,0.6), inset 0 0 0 3px #3a3a40${glow ? `, 0 0 90px ${glow}55` : ''}`,
        position: 'relative',
      }}
    >
      <div
        style={{
          width: '100%',
          height: '100%',
          borderRadius: width * 0.13,
          overflow: 'hidden',
          backgroundColor: '#000',
          position: 'relative',
        }}
      >
        <Img src={staticFile(src)} style={{width: '100%', height: '100%', objectFit: 'cover', objectPosition: 'top'}} />
        <div
          style={{
            position: 'absolute',
            top: width * 0.03,
            left: '50%',
            transform: 'translateX(-50%)',
            width: width * 0.3,
            height: width * 0.085,
            borderRadius: width,
            backgroundColor: '#000',
          }}
        />
      </div>
    </div>
  );
};
