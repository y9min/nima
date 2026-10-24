import React from 'react';
import {
  AbsoluteFill,
  Audio,
  Easing,
  Img,
  OffthreadVideo,
  Sequence,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';
import {loadFont} from '@remotion/google-fonts/Inter';

const {fontFamily} = loadFont('normal', {
  weights: ['500', '600', '700', '800', '900'],
  subsets: ['latin'],
});

const C = {
  ink: '#07140d',
  green: '#08774e',
  mint: '#dff7e9',
  lime: '#d8ff35',
  cream: '#f7f5ec',
  red: '#ff4b55',
  white: '#ffffff',
};

const asset = (name: string) => staticFile(`assets/${name}`);

const fade = (frame: number, duration: number, edge = 8) =>
  interpolate(frame, [0, edge, duration - edge, duration], [0, 1, 1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

const pop = (frame: number, delay = 0, damping = 13) =>
  spring({
    frame: frame - delay,
    fps: 30,
    config: {damping, mass: 0.65, stiffness: 170},
  });

const SoftBackground: React.FC<{dark?: boolean; accent?: string}> = ({
  dark = false,
  accent = C.green,
}) => {
  const frame = useCurrentFrame();
  const drift = Math.sin(frame / 35) * 30;
  return (
    <AbsoluteFill
      style={{
        background: dark
          ? 'radial-gradient(circle at 50% 20%, #26322d 0%, #07100c 68%)'
          : `radial-gradient(circle at 15% 10%, ${C.white} 0%, ${C.cream} 43%, ${C.mint} 100%)`,
        overflow: 'hidden',
      }}
    >
      <div
        style={{
          position: 'absolute',
          width: 850,
          height: 850,
          borderRadius: 999,
          background: accent,
          opacity: dark ? 0.14 : 0.09,
          filter: 'blur(90px)',
          left: -410 + drift,
          top: 960,
        }}
      />
      <div
        style={{
          position: 'absolute',
          width: 550,
          height: 550,
          borderRadius: 999,
          background: C.lime,
          opacity: dark ? 0.05 : 0.12,
          filter: 'blur(80px)',
          right: -280 - drift,
          top: 120,
        }}
      />
    </AbsoluteFill>
  );
};

const AppIcon: React.FC<{
  src: string;
  size?: number;
  rotate?: number;
  shadow?: boolean;
}> = ({src, size = 150, rotate = 0, shadow = true}) => (
  <Img
    src={asset(src)}
    style={{
      width: size,
      height: size,
      borderRadius: size * 0.22,
      objectFit: 'cover',
      transform: `rotate(${rotate}deg)`,
      boxShadow: shadow ? '0 24px 55px rgba(0,0,0,.22)' : undefined,
    }}
  />
);

const BigType: React.FC<{
  children: React.ReactNode;
  size?: number;
  color?: string;
  align?: 'left' | 'center' | 'right';
  lineHeight?: number;
}> = ({children, size = 118, color = C.ink, align = 'center', lineHeight = 0.9}) => (
  <div
    style={{
      fontFamily,
      fontWeight: 900,
      fontSize: size,
      lineHeight,
      color,
      letterSpacing: '-0.065em',
      textAlign: align,
      textTransform: 'uppercase',
    }}
  >
    {children}
  </div>
);

const Pill: React.FC<{children: React.ReactNode; dark?: boolean}> = ({children, dark}) => (
  <div
    style={{
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      padding: '18px 30px',
      borderRadius: 999,
      color: dark ? C.ink : C.white,
      background: dark ? C.lime : C.green,
      fontFamily,
      fontSize: 30,
      fontWeight: 800,
      letterSpacing: '-0.025em',
      boxShadow: '0 14px 35px rgba(0,0,0,.16)',
      textTransform: 'uppercase',
    }}
  >
    {children}
  </div>
);

const VideoCard: React.FC<{
  src: string;
  label: string;
  blocked?: boolean;
  width?: number;
}> = ({src, label, blocked = false, width = 490}) => {
  const frame = useCurrentFrame();
  const s = pop(frame);
  return (
    <div
      style={{
        width,
        borderRadius: 72,
        padding: 12,
        background: blocked ? C.green : C.white,
        boxShadow: '0 32px 80px rgba(0,0,0,.28)',
        transform: `scale(${interpolate(s, [0, 1], [0.72, 1])}) translateY(${interpolate(
          s,
          [0, 1],
          [80, 0],
        )}px)`,
      }}
    >
      <div style={{position: 'relative', borderRadius: 61, overflow: 'hidden'}}>
        <OffthreadVideo
          muted
          src={asset(src)}
          style={{width: '100%', display: 'block'}}
        />
        <div
          style={{
            position: 'absolute',
            left: 18,
            right: 18,
            top: 18,
            display: 'flex',
            justifyContent: 'center',
          }}
        >
          <Pill dark={blocked}>{label}</Pill>
        </div>
      </div>
    </div>
  );
};

const HookScene: React.FC = () => {
  const frame = useCurrentFrame();
  const s1 = pop(frame, 0);
  const s2 = pop(frame, 6);
  const slash = interpolate(frame, [13, 25], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.out(Easing.cubic),
  });
  return (
    <AbsoluteFill style={{opacity: fade(frame, 45, 5)}}>
      <SoftBackground />
      <div
        style={{
          position: 'absolute',
          top: 260,
          left: 95,
          right: 95,
          transform: `translateY(${interpolate(s1, [0, 1], [90, 0])}px) scale(${interpolate(
            s1,
            [0, 1],
            [0.72, 1],
          )})`,
        }}
      >
        <BigType size={142}>Delete</BigType>
        <div style={{position: 'relative'}}>
          <BigType size={205} color={C.green}>
            Reels
          </BigType>
          <div
            style={{
              position: 'absolute',
              height: 22,
              borderRadius: 20,
              background: C.red,
              left: `${50 - slash * 49}%`,
              right: `${50 - slash * 49}%`,
              top: '50%',
              transform: 'rotate(-7deg)',
              boxShadow: '0 8px 20px rgba(255,75,85,.4)',
            }}
          />
        </div>
        <BigType size={91}>from Instagram</BigType>
      </div>
      <div
        style={{
          position: 'absolute',
          bottom: 180,
          left: 0,
          right: 0,
          display: 'flex',
          justifyContent: 'center',
          gap: 50,
          transform: `scale(${s2})`,
        }}
      >
        <AppIcon src="instagram.png" size={170} rotate={-8} />
        <div style={{fontFamily, fontWeight: 900, fontSize: 110, color: C.ink}}>→</div>
        <AppIcon src="nima.jpg" size={170} rotate={8} />
      </div>
    </AbsoluteFill>
  );
};

const InstagramScene: React.FC = () => {
  const frame = useCurrentFrame();
  const localSwitch = frame >= 36;
  const iconScale = pop(frame, 4);
  return (
    <AbsoluteFill style={{opacity: fade(frame, 75)}}>
      <SoftBackground accent="#e33b9a" />
      <div style={{position: 'absolute', top: 90, left: 80, right: 80}}>
        <BigType size={78}>
          Instagram,
          <br />
          <span style={{color: C.green}}>without the trap.</span>
        </BigType>
      </div>
      <div style={{position: 'absolute', top: 330, left: 295}}>
        {!localSwitch ? (
          <VideoCard src="ig_scrolling.mp4" label="THE SCROLL" />
        ) : (
          <VideoCard src="ig_scrolling_blocked.mp4" label="REELS BLOCKED" blocked />
        )}
      </div>
      <div
        style={{
          position: 'absolute',
          right: 90,
          bottom: 170,
          transform: `scale(${iconScale}) rotate(8deg)`,
        }}
      >
        <AppIcon src="nima.jpg" size={150} />
      </div>
    </AbsoluteFill>
  );
};

const TikTokScene: React.FC = () => {
  const frame = useCurrentFrame();
  const switchAt = 56;
  const blocked = frame >= switchAt;
  const title = pop(frame, 4);
  const kitty = pop(frame, 80);
  return (
    <AbsoluteFill style={{opacity: fade(frame, 165)}}>
      <SoftBackground accent="#18c9cf" />
      <div
        style={{
          position: 'absolute',
          left: 70,
          right: 70,
          top: 86,
          transform: `translateY(${interpolate(title, [0, 1], [-55, 0])}px)`,
        }}
      >
        <BigType size={78}>
          Remove the
          <br />
          <span style={{color: C.green}}>For You page.</span>
        </BigType>
      </div>
      <div style={{position: 'absolute', top: 330, left: 295}}>
        {!blocked ? (
          <VideoCard src="tiktok_scrolling.mp4" label="DISTRACTED" />
        ) : (
          <VideoCard src="tiktok_scrolling_blocked.mp4" label="FYP BLOCKED" blocked />
        )}
      </div>
      <div
        style={{
          position: 'absolute',
          left: 55,
          bottom: 70,
          transform: `scale(${kitty}) rotate(-5deg)`,
          transformOrigin: 'bottom center',
        }}
      >
        <Img src={asset('kitty-default.png')} style={{width: 300, height: 390, objectFit: 'contain'}} />
      </div>
      <div
        style={{
          position: 'absolute',
          right: 50,
          bottom: 190,
          transform: `scale(${pop(frame, 90)}) rotate(5deg)`,
        }}
      >
        <Pill>Stay connected</Pill>
      </div>
      <div
        style={{
          position: 'absolute',
          right: 100,
          bottom: 55,
          opacity: interpolate(frame, [108, 118], [0, 1], {extrapolateLeft: 'clamp'}),
        }}
      >
        <Pill dark>Not distracted</Pill>
      </div>
    </AbsoluteFill>
  );
};

const ProblemScene: React.FC = () => {
  const frame = useCurrentFrame();
  const phone = pop(frame, 2);
  const shake = frame > 52 ? Math.sin(frame * 1.7) * 9 : 0;
  const strike = interpolate(frame, [55, 75], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  return (
    <AbsoluteFill style={{opacity: fade(frame, 141)}}>
      <SoftBackground dark accent={C.red} />
      <div style={{position: 'absolute', left: 55, right: 55, top: 90}}>
        <BigType size={80} color={C.white}>
          Screen Time
          <br />
          <span style={{color: '#9baba2'}}>doesn’t stop you.</span>
        </BigType>
      </div>
      <div
        style={{
          position: 'absolute',
          left: 170,
          top: 360,
          transform: `translateX(${shake}px) scale(${interpolate(phone, [0, 1], [0.72, 1])})`,
        }}
      >
        <Img
          src={asset('screentime-high.png')}
          style={{width: 740, height: 1110, objectFit: 'contain', filter: 'drop-shadow(0 35px 55px rgba(0,0,0,.55))'}}
        />
        <div
          style={{
            position: 'absolute',
            height: 28,
            borderRadius: 30,
            background: C.red,
            left: `${50 - strike * 48}%`,
            right: `${50 - strike * 48}%`,
            top: '46%',
            transform: 'rotate(-12deg)',
          }}
        />
      </div>
      <Img
        src={asset('kitty-stressed.png')}
        style={{
          position: 'absolute',
          width: 345,
          height: 345,
          objectFit: 'contain',
          right: 25,
          bottom: 55,
          transform: `scale(${pop(frame, 77)}) rotate(7deg)`,
        }}
      />
      <div
        style={{
          position: 'absolute',
          left: 70,
          bottom: 120,
          transform: `scale(${pop(frame, 92)})`,
        }}
      >
        <BigType size={90} color={C.red} align="left">
          You tried it.
        </BigType>
        <div style={{fontFamily, color: C.white, fontSize: 43, fontWeight: 700, marginTop: 18}}>
          It didn’t work.
        </div>
      </div>
    </AbsoluteFill>
  );
};

const SolutionScene: React.FC = () => {
  const frame = useCurrentFrame();
  const phone = pop(frame, 6);
  const orbit = frame / 2.2;
  return (
    <AbsoluteFill style={{opacity: fade(frame, 123)}}>
      <SoftBackground accent={C.lime} />
      <div style={{position: 'absolute', left: 50, right: 50, top: 80}}>
        <BigType size={88}>
          Nima removes
          <br />
          <span style={{color: C.green}}>the distraction.</span>
        </BigType>
      </div>
      <div
        style={{
          position: 'absolute',
          top: 350,
          left: 188,
          transform: `translateY(${interpolate(phone, [0, 1], [100, 0])}px) scale(${interpolate(
            phone,
            [0, 1],
            [0.78, 1],
          )})`,
        }}
      >
        <Img
          src={asset('nima-both-blocked.png')}
          style={{width: 705, height: 1240, objectFit: 'contain', filter: 'drop-shadow(0 32px 55px rgba(0,50,25,.28))'}}
        />
      </div>
      <div
        style={{position: 'absolute', left: 70 + Math.sin(orbit / 13) * 20, top: 660, transform: 'rotate(-9deg)'}}
      >
        <AppIcon src="instagram.png" size={145} />
      </div>
      <div
        style={{position: 'absolute', right: 65 + Math.cos(orbit / 14) * 18, top: 1000, transform: 'rotate(9deg)'}}
      >
        <AppIcon src="tiktok.png" size={145} />
      </div>
      <div
        style={{
          position: 'absolute',
          left: 0,
          right: 0,
          bottom: 78,
          display: 'flex',
          justifyContent: 'center',
          transform: `scale(${pop(frame, 60)})`,
        }}
      >
        <Pill dark>Keep the important parts</Pill>
      </div>
    </AbsoluteFill>
  );
};

const DmsScene: React.FC = () => {
  const frame = useCurrentFrame();
  const card = pop(frame, 3);
  const bubble = pop(frame, 27);
  return (
    <AbsoluteFill style={{opacity: fade(frame, 108)}}>
      <SoftBackground accent="#dd38c5" />
      <div style={{position: 'absolute', left: 55, right: 55, top: 80}}>
        <BigType size={87}>
          DMs stay.
          <br />
          <span style={{color: C.green}}>The scroll goes.</span>
        </BigType>
      </div>
      <div
        style={{
          position: 'absolute',
          left: 215,
          top: 370,
          transform: `scale(${interpolate(card, [0, 1], [0.75, 1])}) rotate(${interpolate(
            card,
            [0, 1],
            [-4, 0],
          )}deg)`,
        }}
      >
        <Img
          src={asset('instagram-dms.png')}
          style={{width: 650, height: 1190, objectFit: 'contain', filter: 'drop-shadow(0 35px 60px rgba(0,0,0,.22))'}}
        />
      </div>
      <div
        style={{
          position: 'absolute',
          right: 38,
          top: 660,
          width: 400,
          padding: '28px 32px',
          borderRadius: 34,
          background: C.white,
          boxShadow: '0 20px 50px rgba(0,0,0,.18)',
          transform: `scale(${bubble}) translateY(${interpolate(bubble, [0, 1], [40, 0])}px)`,
        }}
      >
        <div style={{fontFamily, fontWeight: 800, fontSize: 31, color: C.ink}}>Instagram</div>
        <div style={{fontFamily, fontWeight: 600, fontSize: 28, color: '#58625c', marginTop: 7}}>
          New message from kitty 🎀
        </div>
      </div>
      <Img
        src={asset('kitty-smug.png')}
        style={{
          position: 'absolute',
          width: 300,
          height: 300,
          objectFit: 'contain',
          left: 30,
          bottom: 55,
          transform: `scale(${pop(frame, 53)}) rotate(-6deg)`,
        }}
      />
    </AbsoluteFill>
  );
};

const FinaleScene: React.FC = () => {
  const frame = useCurrentFrame();
  const logo = pop(frame, 0, 11);
  const line2 = pop(frame, 13, 12);
  const listing = pop(frame, 30, 14);
  const cta = pop(frame, 50, 11);
  return (
    <AbsoluteFill style={{background: C.ink, opacity: fade(frame, 96, 5)}}>
      <div
        style={{
          position: 'absolute',
          width: 920,
          height: 920,
          borderRadius: 999,
          background: C.green,
          filter: 'blur(120px)',
          opacity: 0.45,
          left: 80,
          top: -500,
        }}
      />
      <div
        style={{
          position: 'absolute',
          left: 70,
          right: 70,
          top: 95,
          transform: `scale(${logo})`,
        }}
      >
        <BigType size={108} color={C.white}>
          Instagram,
        </BigType>
      </div>
      <div
        style={{
          position: 'absolute',
          left: 65,
          right: 65,
          top: 210,
          transform: `scale(${line2})`,
        }}
      >
        <BigType size={136} color={C.lime}>
          Social again.
        </BigType>
      </div>
      <Img
        src={asset('appstore-listing.png')}
        style={{
          position: 'absolute',
          width: 900,
          height: 800,
          objectFit: 'contain',
          left: 90,
          top: 500,
          borderRadius: 48,
          transform: `scale(${listing})`,
          filter: 'drop-shadow(0 35px 70px rgba(0,0,0,.45))',
        }}
      />
      <Img
        src={asset('kitty-thumbsup.png')}
        style={{
          position: 'absolute',
          width: 360,
          height: 360,
          objectFit: 'contain',
          right: 22,
          bottom: 95,
          transform: `scale(${pop(frame, 40)}) rotate(5deg)`,
        }}
      />
      <div
        style={{
          position: 'absolute',
          left: 80,
          bottom: 165,
          transform: `scale(${cta})`,
        }}
      >
        <Pill dark>Download Nima</Pill>
      </div>
      <div
        style={{
          position: 'absolute',
          left: 84,
          bottom: 100,
          color: '#aebcb4',
          fontFamily,
          fontWeight: 600,
          fontSize: 28,
        }}
      >
        Keep social. Not scrolling.
      </div>
    </AbsoluteFill>
  );
};

const ProgressBar: React.FC = () => {
  const frame = useCurrentFrame();
  return (
    <div
      style={{
        position: 'absolute',
        left: 38,
        right: 38,
        bottom: 28,
        height: 7,
        borderRadius: 99,
        overflow: 'hidden',
        background: 'rgba(255,255,255,.25)',
        zIndex: 100,
      }}
    >
      <div
        style={{
          width: `${(frame / 719) * 100}%`,
          height: '100%',
          borderRadius: 99,
          background: C.lime,
        }}
      />
    </div>
  );
};

type CaptionCue = {
  start: number;
  end: number;
  text: string;
};

const captionCues: CaptionCue[] = [
  {start: 0.0, end: 0.62, text: 'DELETE REELS'},
  {start: 0.62, end: 1.08, text: 'FROM INSTAGRAM'},
  {start: 1.22, end: 1.88, text: 'WE CREATED AN APP'},
  {start: 1.88, end: 2.66, text: 'THAT BLOCKS REELS'},
  {start: 2.66, end: 3.18, text: 'FROM INSTAGRAM'},
  {start: 3.4, end: 4.64, text: 'IT CAN REMOVE THE FOR YOU PAGE'},
  {start: 4.64, end: 5.2, text: 'FROM TIKTOK'},
  {start: 5.2, end: 6.34, text: 'SO YOU CAN ACTUALLY'},
  {start: 6.34, end: 7.08, text: 'STAY CONNECTED'},
  {start: 7.08, end: 8.34, text: 'WITHOUT BEING DISTRACTED'},
  {start: 9.1, end: 10.7, text: 'ALL OF THE BS SCREEN TIME BLOCKERS'},
  {start: 10.7, end: 11.16, text: "DON'T WORK"},
  {start: 11.52, end: 12.06, text: 'YOU KNOW THAT'},
  {start: 12.38, end: 13.34, text: 'YOU PROBABLY TRIED THEM'},
  {start: 13.72, end: 14.46, text: 'WHEREAS NIMA ACTUALLY'},
  {start: 14.46, end: 15.56, text: 'REMOVES THE DISTRACTIONS'},
  {start: 15.56, end: 17.04, text: 'AND KEEPS THE IMPORTANT PARTS'},
  {start: 17.64, end: 18.66, text: 'YOU CAN STILL SEE YOUR FRIENDS'},
  {start: 18.66, end: 19.44, text: 'DMS'},
  {start: 19.44, end: 20.68, text: 'AND ALL OF THE IMPORTANT THINGS'},
  {start: 20.9, end: 21.76, text: 'NIMA ACTUALLY MAKES'},
  {start: 21.76, end: 22.96, text: 'INSTAGRAM SOCIAL AGAIN'},
];

const LiveCaptions: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const time = frame / fps;
  const cue = captionCues.find(({start, end}) => time >= start && time < end);

  if (!cue) return null;

  const cueFrame = frame - Math.round(cue.start * fps);
  const entrance = spring({
    frame: cueFrame,
    fps,
    config: {damping: 18, stiffness: 250, mass: 0.45},
  });

  return (
    <div
      style={{
        position: 'absolute',
        zIndex: 300,
        left: 62,
        right: 62,
        bottom: 245,
        display: 'flex',
        justifyContent: 'center',
        pointerEvents: 'none',
        transform: `translateY(${interpolate(entrance, [0, 1], [18, 0])}px) scale(${interpolate(
          entrance,
          [0, 1],
          [0.94, 1],
        )})`,
        opacity: interpolate(entrance, [0, 1], [0, 1]),
      }}
    >
      <div
        style={{
          maxWidth: 940,
          color: C.white,
          fontFamily,
          fontSize: cue.text.length > 28 ? 49 : cue.text.length > 18 ? 56 : 64,
          fontWeight: 900,
          lineHeight: 1.04,
          letterSpacing: '-0.035em',
          textAlign: 'center',
          textTransform: 'uppercase',
          WebkitTextStroke: '10px #000000',
          paintOrder: 'stroke fill',
          filter: 'drop-shadow(0 5px 2px rgba(0,0,0,.32))',
        }}
      >
        {cue.text}
      </div>
    </div>
  );
};

export const NimaSocialAd: React.FC = () => {
  return (
    <AbsoluteFill style={{background: C.cream}}>
      <Audio src={asset('voiceover.mp3')} volume={1} />
      {[36, 102, 267, 402, 522, 624].map((from) => (
        <Sequence key={`whoosh-${from}`} from={from} durationInFrames={12}>
          <Audio src={asset('whoosh.wav')} volume={0.42} />
        </Sequence>
      ))}
      {[72, 158, 457].map((from) => (
        <Sequence key={`click-${from}`} from={from} durationInFrames={5}>
          <Audio src={asset('click.wav')} volume={0.7} />
        </Sequence>
      ))}
      <Sequence from={0} durationInFrames={45} premountFor={15}>
        <HookScene />
      </Sequence>
      <Sequence from={36} durationInFrames={75} premountFor={15}>
        <InstagramScene />
      </Sequence>
      <Sequence from={102} durationInFrames={165} premountFor={20}>
        <TikTokScene />
      </Sequence>
      <Sequence from={267} durationInFrames={141} premountFor={20}>
        <ProblemScene />
      </Sequence>
      <Sequence from={402} durationInFrames={123} premountFor={20}>
        <SolutionScene />
      </Sequence>
      <Sequence from={522} durationInFrames={108} premountFor={20}>
        <DmsScene />
      </Sequence>
      <Sequence from={624} durationInFrames={96} premountFor={20}>
        <FinaleScene />
      </Sequence>
      <LiveCaptions />
      <ProgressBar />
    </AbsoluteFill>
  );
};
