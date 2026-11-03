import {
  AbsoluteFill, Audio, Img, OffthreadVideo, Sequence, interpolate, spring, staticFile,
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
  fadeS?: number;        // overrides the project's fade; 0 for a cut that continues the last clip
};

// The closing beat: the last clip's final frame (exported as a still) blurs and
// darkens, the trip's figures count up, a headline lands, then the app icon.
// Figures are copied from the film's own end card, never computed here.
export type Outro = {
  bg: string;            // a still of the frame the last clip ends on
  durationS: number;
  stats?: { value: number; unit: string }[];
  headline?: string;
  icon?: string;
  name?: string;
  tagline?: string;
};

export type PromoProps = {
  clips: Clip[];
  title?: string;        // the opening card; omit for App Store previews
  endCard?: string;      // e.g. the app name and "on the App Store"
  music?: string;
  musicFromS?: number;   // where in the music file to start
  fadeS?: number;        // each clip fades in from black over this long
  // Kamome films keep stop names and attribution at the bottom: "top" clears them.
  captionAt?: "top" | "bottom";
  voice?: string;        // a voice-over made by Tools/kamome-voice.py
  musicVolume?: number;
  // The voice-over's own lines, timed from the start of the video. Paste them
  // from captions/<script>.cues.json; seconds include the title card. Both sit
  // at the bottom: use these or the clips' own captions, not both at once.
  voiceCaptions?: { fromS: number; toS: number; text: string }[];
  outro?: Outro;
  accent?: string;       // the outro's figures; defaults to the films' route cyan
};

const CARD_S = 2;
const MUSIC_FADE_IN_S = 0.5;
const MUSIC_FADE_OUT_S = 1.5;

const FadeIn: React.FC<{ seconds: number; children: React.ReactNode }> = ({ seconds, children }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const opacity = seconds > 0
    ? interpolate(frame, [0, seconds * fps], [0, 1], { extrapolateRight: "clamp" }) : 1;
  return <AbsoluteFill style={{ opacity }}>{children}</AbsoluteFill>;
};

export const promoFrames = (p: PromoProps, fps: number) =>
  Math.max(1, Math.round(fps * (p.clips.reduce((s, c) => s + c.durationS, 0)
    + (p.title ? CARD_S : 0) + (p.outro?.durationS ?? 0) + (p.endCard ? CARD_S : 0))));

const FONT = "-apple-system, 'PingFang TC', sans-serif";

const OutroBeat: React.FC<{ o: Outro; accent: string }> = ({ o, accent }) => {
  const frame = useCurrentFrame();
  const { fps, width } = useVideoConfig();
  const t = frame / fps;
  // The background starts sharp, as the last clip left it, so the cut is invisible.
  const blur = interpolate(t, [0, 0.6], [0, 10], { extrapolateRight: "clamp" });
  const dim = interpolate(t, [0, 0.6], [1, 0.5], { extrapolateRight: "clamp" });
  const zoom = interpolate(t, [0, o.durationS], [1, 1.12]);
  const pop = (atS: number, damping = 12) =>
    spring({ frame: frame - atS * fps, fps, config: { damping, mass: 0.6 } });
  const stats = o.stats ?? [];
  const statsAt = 0.35, headlineAt = 0.35 + stats.length * 0.15 + 0.55, iconAt = headlineAt + 0.8;
  return (
    <AbsoluteFill style={{ background: "black", overflow: "hidden" }}>
      <Img src={staticFile(o.bg)} style={{
        width: "100%", height: "100%", objectFit: "cover",
        transform: `scale(${zoom})`, filter: `blur(${blur}px) brightness(${dim})`,
      }} />
      <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", fontFamily: FONT, color: "white" }}>
        <div style={{ display: "flex", gap: width * 0.07, marginBottom: width * 0.1 }}>
          {stats.map((s, i) => {
            const at = statsAt + i * 0.15;
            const k = pop(at);
            const count = interpolate(t, [at, at + 0.9], [0, s.value],
              { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: (x) => 1 - Math.pow(1 - x, 3) });
            return (
              <div key={i} style={{ textAlign: "center", opacity: k, transform: `translateY(${(1 - k) * 40}px)` }}>
                <div style={{ fontSize: width * 0.115, fontWeight: 800, color: accent, lineHeight: 1,
                  fontVariantNumeric: "tabular-nums" }}>
                  {Math.round(count).toLocaleString("en-US")}
                </div>
                <div style={{ fontSize: width * 0.042, fontWeight: 600, marginTop: width * 0.015, opacity: 0.9 }}>{s.unit}</div>
              </div>
            );
          })}
        </div>
        {o.headline ? (
          <div style={{
            fontSize: width * 0.085, fontWeight: 800, textAlign: "center", whiteSpace: "pre-line",
            lineHeight: 1.3, padding: `0 ${width * 0.08}px`, textWrap: "balance",
            opacity: pop(headlineAt, 14), transform: `scale(${0.85 + 0.15 * pop(headlineAt, 14)})`,
            textShadow: "0 4px 24px rgba(0,0,0,0.5)",
          }}>{o.headline}</div>
        ) : null}
        {o.icon ? (
          <div style={{ marginTop: width * 0.11, display: "flex", flexDirection: "column", alignItems: "center",
            opacity: pop(iconAt), transform: `scale(${0.6 + 0.4 * pop(iconAt, 9)})` }}>
            <Img src={staticFile(o.icon)} style={{ width: width * 0.22, height: width * 0.22,
              borderRadius: width * 0.05, boxShadow: "0 12px 40px rgba(0,0,0,0.45)" }} />
            {o.name ? <div style={{ fontSize: width * 0.06, fontWeight: 700, marginTop: width * 0.035 }}>{o.name}</div> : null}
            {o.tagline ? <div style={{ fontSize: width * 0.036, opacity: 0.8, marginTop: width * 0.012 }}>{o.tagline}</div> : null}
          </div>
        ) : null}
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

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

const Caption: React.FC<{ text: string; at?: "top" | "bottom" }> = ({ text, at = "bottom" }) => {
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();
  const y = interpolate(frame, [0, fps * 0.35], [20, 0], { extrapolateRight: "clamp" });
  const opacity = interpolate(frame, [0, fps * 0.35], [0, 1], { extrapolateRight: "clamp" });
  return (
    <AbsoluteFill style={at === "top"
      ? { justifyContent: "flex-start", alignItems: "center", paddingTop: height * 0.08 }
      : { justifyContent: "flex-end", alignItems: "center", paddingBottom: height * 0.09 }}>
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
  const { fps, durationInFrames } = useVideoConfig();
  const musicLevel = p.musicVolume ?? (p.voice ? 0.35 : 1);
  const musicVolume = (f: number) => musicLevel * interpolate(
    f, [0, MUSIC_FADE_IN_S * fps, durationInFrames - MUSIC_FADE_OUT_S * fps, durationInFrames],
    [0, 1, 1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
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
        <FadeIn seconds={c.fadeS ?? p.fadeS ?? 0}>
          <OffthreadVideo
            src={staticFile(c.file)} muted
            startFrom={Math.round((c.fromS ?? 0) * fps)}
            style={{ width: "100%", height: "100%", objectFit: c.fit ?? "cover" }}
          />
        </FadeIn>
        {c.caption ? <Caption text={c.caption} at={p.captionAt} /> : null}
      </Sequence>,
    );
    at += len;
  });
  if (p.outro) {
    const len = Math.round(p.outro.durationS * fps);
    seq.push(<Sequence key="outro" from={at} durationInFrames={len}><OutroBeat o={p.outro} accent={p.accent ?? "#5cc8e0"} /></Sequence>);
    at += len;
  }
  if (p.endCard) {
    seq.push(<Sequence key="end" from={at} durationInFrames={CARD_S * fps}><Card text={p.endCard} /></Sequence>);
  }
  return (
    <AbsoluteFill style={{ background: "black" }}>
      {seq}
      {(p.voiceCaptions ?? []).map((c, i) => (
        <Sequence key={`vc-${i}`} from={Math.round(c.fromS * fps)}
          durationInFrames={Math.max(1, Math.round((c.toS - c.fromS) * fps))}>
          <Caption text={c.text} at={p.captionAt} />
        </Sequence>
      ))}
      {p.music ? (
        <Audio src={staticFile(p.music)} volume={musicVolume}
          startFrom={Math.round((p.musicFromS ?? 0) * fps)} />
      ) : null}
      {p.voice ? <Audio src={staticFile(p.voice)} /> : null}
    </AbsoluteFill>
  );
};
