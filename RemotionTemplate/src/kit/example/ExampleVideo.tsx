import React from 'react';
import {AbsoluteFill} from 'remotion';
import {
  AppIcon,
  Caption,
  Chip,
  Flash,
  Kinetic,
  Notification,
  Particles,
  Phone,
  ProbabilityBar,
  Sfx,
  Spotlight,
  Timeline,
  Vignette,
  fonts,
  useShake,
  type StudioProps,
} from '..';

/** Example use of the kit: hook → product → data → notification → CTA. New videos should not copy it; it is only a reference. */
export const ExampleVideo: React.FC<StudioProps> = ({brand, lang, scenes}) => (
  <AbsoluteFill lang={lang} style={{backgroundColor: brand.background}}>
    <Spotlight color={`${brand.primary}88`} base={brand.background} pulse />
    <Timeline
      scenes={scenes}
      overlap={6}
      render={(i, scene) => {
        const asset = scene.assets[0];
        switch (i) {
          case 0:
            return <Hook text={scene.text} accent={brand.accent} />;
          case 1:
            return (
              <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', gap: 60}}>
                <Kinetic text={scene.text} size={96} accent={brand.accent} />
                {asset ? <Phone src={asset} width={520} glow={brand.primary} tilt={-8} delay={6} /> : null}
                <Sfx sound="whoosh" />
              </AbsoluteFill>
            );
          case 2:
            return (
              <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', gap: 80, padding: 80}}>
                <Kinetic text={scene.text} size={92} accent={brand.accent} />
                <ProbabilityBar values={[48, 27, 25]} colors={[brand.primary, '#94a3b8', brand.accent]} labels={['Home', 'Draw', 'Away']} width={900} start={10} />
              </AbsoluteFill>
            );
          case 3:
            return (
              <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', gap: 50}}>
                <Chip label="LIVE" color="#dc2626" pulse />
                <Notification title={brand.appName} body={scene.text.replace(/\*/g, '')} icon={brand.logo} width={920} delay={8} />
                <Sfx sound="notification" at={8} />
              </AbsoluteFill>
            );
          default:
            return (
              <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', gap: 50}}>
                <Particles colors={[brand.accent, brand.primary, '#fff']} />
                {brand.logo ? <AppIcon src={brand.logo} size={260} glow={brand.accent} /> : null}
                <Kinetic text={scene.text} size={110} accent={brand.accent} animation="pop" delay={8} />
                <Caption text={brand.storeLabel ?? 'App Store'} accent={brand.accent} delay={20} />
              </AbsoluteFill>
            );
        }
      }}
    />
    <Vignette />
  </AbsoluteFill>
);

const Hook: React.FC<{text: string; accent: string}> = ({text, accent}) => {
  const shake = useShake(4, 22);
  return (
    <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center', padding: 80, transform: `translate(${shake.x}px, ${shake.y}px)`}}>
      <Kinetic text={text} size={150} accent={accent} animation="slam" family={fonts.display} />
      <Flash at={4} />
      <Sfx sound="boom" at={4} />
    </AbsoluteFill>
  );
};
