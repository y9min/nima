import React from 'react';
import {Composition} from 'remotion';
import {NimaSocialAd} from './NimaSocialAd';

export const Root: React.FC = () => (
  <Composition
    id="NimaSocialAd"
    component={NimaSocialAd}
    durationInFrames={720}
    fps={30}
    width={1080}
    height={1920}
  />
);
