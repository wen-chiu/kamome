import {
  AbsoluteFill, Audio, OffthreadVideo, Sequence, interpolate, staticFile,
  useCurrentFrame, useVideoConfig,
} from "remotion";

// Every file named here is relative to ~/Kamome-promo/footage (Remotion's public
// dir). Nothing in this template knows a place: captions and titles come from the
// props file, which lives outside the repository.
export type Clip = {
  file: string;          // an app capture or a rendered Kamome film
  fromS?: number;        // where in the file the clip starts
  durationS: number;
  caption?: string;      // a short overlay; Apple allows text that explains the app
  fit?: "cover" | "contain";
};

export type PromoProps = {
  clips: Clip[];
  title?: string;        // the opening card; omit for App Store previews
  endCard?: string;      // e.g. the app name and "on the App Store"
  music?: string;
  voice?: string;        // a voice-over made by Tools/kamome-voice.py
  musicVolume?: number;
  // The voice-over's own lines, timed from the start of the video. Paste them
  // from captions/<script>.cues.json; seconds include the title card. Both sit
  // at the bottom: use these or the clips' own captions, not both at once.
  voiceCaptions?: { fromS: number; toS: number; text: string }[];
};

const CARD_S = 2;

export const promoFrames = (p: PromoProps, fps: number) =>
  Math.round(fps * (p.clips.reduce((s, c) => s + c.durationS, 0)
    + (p.title ? CARD_S : 0) + (p.endCard ? CARD_S : 0)));

const Card: React.FC<{ text: string }> = ({ text }) => {
  const frame = useCurrentFrame();
  const { fps, width } = useVideoConfig();
  const opacity = interpolate(frame, [0, fps * 0.4, fps * (CARD_S - 0.4), fps * CARD_S], [0, 1, 1, 0]);
  return (
    <AbsoluteFill style={{ background: "#0d0f12", justifyContent: "center", alignItems: "center" }}>
      <div style={{
        opacity, color: "#f4efe6", fontSize: width * 0.065, fontWeight: 600,
        fontFamily: "-apple-system, 'PingFang TC', sans-serif", textAlign: "center",
        padding: width * 0.08, whiteSpace: "pre-line", lineHeight: 1.3,
      }}>{text}</div>
    </AbsoluteFill>
  );
};

const Caption: React.FC<{ text: string }> = ({ text }) => {
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();
  const y = interpolate(frame, [0, fps * 0.35], [20, 0], { extrapolateRight: "clamp" });
  const opacity = interpolate(frame, [0, fps * 0.35], [0, 1], { extrapolateRight: "clamp" });
  return (
    <AbsoluteFill style={{ justifyContent: "flex-end", alignItems: "center", paddingBottom: height * 0.09 }}>
      <div style={{
        opacity, transform: `translateY(${y}px)`, color: "white", fontSize: width * 0.05,
        fontWeight: 600, fontFamily: "-apple-system, 'PingFang TC', sans-serif",
        background: "rgba(0,0,0,0.45)", borderRadius: width * 0.03,
        padding: `${width * 0.02}px ${width * 0.045}px`, textAlign: "center", maxWidth: "86%",
        textWrap: "balance",
      }}>{text}</div>
    </AbsoluteFill>
  );
};

export const Promo: React.FC<PromoProps> = (p) => {
  const { fps } = useVideoConfig();
  let at = 0;
  const seq: React.ReactNode[] = [];
  if (p.title) {
    seq.push(<Sequence key="title" from={0} durationInFrames={CARD_S * fps}><Card text={p.title} /></Sequence>);
    at += CARD_S * fps;
  }
  p.clips.forEach((c, i) => {
    const len = Math.round(c.durationS * fps);
    seq.push(
      <Sequence key={`clip-${i}`} from={at} durationInFrames={len}>
        <AbsoluteFill style={{ background: "black" }}>
          <OffthreadVideo
            src={staticFile(c.file)} muted
            startFrom={Math.round((c.fromS ?? 0) * fps)}
            style={{ width: "100%", height: "100%", objectFit: c.fit ?? "cover" }}
          />
        </AbsoluteFill>
        {c.caption ? <Caption text={c.caption} /> : null}
      </Sequence>,
    );
    at += len;
  });
  if (p.endCard) {
    seq.push(<Sequence key="end" from={at} durationInFrames={CARD_S * fps}><Card text={p.endCard} /></Sequence>);
  }
  return (
    <AbsoluteFill style={{ background: "black" }}>
      {seq}
      {(p.voiceCaptions ?? []).map((c, i) => (
        <Sequence key={`vc-${i}`} from={Math.round(c.fromS * fps)}
          durationInFrames={Math.max(1, Math.round((c.toS - c.fromS) * fps))}>
          <Caption text={c.text} />
        </Sequence>
      ))}
      {p.music ? <Audio src={staticFile(p.music)} volume={p.musicVolume ?? (p.voice ? 0.35 : 1)} /> : null}
      {p.voice ? <Audio src={staticFile(p.voice)} /> : null}
    </AbsoluteFill>
  );
};
