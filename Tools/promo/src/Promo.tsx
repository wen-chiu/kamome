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
  captionAt?: "top" | "bottom"; // overrides the project's caption position
  rate?: number;         // playback speed: the clip spends durationS × rate of the source
};

// The opening: a title over a phone that plays an app capture (a simulator
// recording: home screen, tap Kamome, the app opens), then the camera falls into
// the phone's screen and the film takes over. Simulator captures include the
// Dynamic Island, so the frame draws only the bezel.
export type Intro = {
  file: string;          // the screen recording, portrait
  fromS?: number;
  durationS: number;
  title?: string;
  zoomS?: number;        // the last seconds, spent zooming into the screen (0.8)
  screenAspect?: number; // width / height of the recording (1206 / 2622 for a 6.3" iPhone)
  // A finger's tap, drawn because a launch from simctl shows none: when (seconds
  // into the intro) and where (fractions of the screen).
  tap?: { atS: number; x: number; y: number };
  // "tap" dives into the tapped point (the app icon) instead of the whole screen,
  // so the intro can end before the launch animation's white window.
  zoomInto?: "screen" | "tap";
};

// A pointing hand that glides in, rests on the target and presses on the tap.
const Pointer: React.FC<{ atS: number; x: number; y: number; size: number; screenW: number; screenH: number }> =
  ({ atS, x, y, size, screenW, screenH }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const t = frame / fps;
  const enter = atS - 1.1, arrive = atS - 0.25;
  if (t < enter) return null;
  const k = interpolate(t, [enter, arrive], [0, 1],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: (v) => 1 - Math.pow(1 - v, 3) });
  // From the lower right of the screen to the target; the fingertip is the emoji's top-left third.
  const px = interpolate(k, [0, 1], [screenW * 0.95, x]), py = interpolate(k, [0, 1], [screenH * 0.75, y]);
  const press = interpolate(t, [atS - 0.08, atS, atS + 0.12], [1, 0.82, 1],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  // Gone once it has pressed, so the dive into the icon does not magnify it.
  const opacity = interpolate(t, [enter, enter + 0.2, atS + 0.04, atS + 0.12], [0, 1, 1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return (
    <div style={{
      position: "absolute", left: px - size * 0.36, top: py - size * 0.08, fontSize: size, lineHeight: 1,
      transform: `scale(${press})`, transformOrigin: "36% 8%", opacity,
      filter: "drop-shadow(0 6px 10px rgba(0,0,0,0.45))",
    }}>👆</div>
  );
};

const TapRipple: React.FC<{ atS: number; x: number; y: number; size: number }> = ({ atS, x, y, size }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const t = frame / fps - atS;
  if (t < 0 || t > 0.3) return null;  // over before the dive starts
  const k = t / 0.3;
  return (
    <div style={{
      position: "absolute", left: x - size / 2, top: y - size / 2, width: size, height: size,
      borderRadius: size, background: "rgba(20,30,40,0.35)", border: `${size * 0.05}px solid white`,
      boxShadow: "0 0 12px rgba(0,0,0,0.35)", transform: `scale(${0.5 + 0.7 * k})`, opacity: 1 - k * k,
    }} />
  );
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
  speed?: number;        // >1 lands the figures, headline and icon sooner, for a short cut
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
  captionSize?: number;  // caption type as a fraction of the frame width (0.05)
  // Distance from the frame's edge as a fraction of its height (0.08 top, 0.09
  // bottom). A letterboxed film's bands hold the captions with small insets.
  captionInset?: { top?: number; bottom?: number };
  voice?: string;        // a voice-over made by Tools/kamome-voice.py
  musicVolume?: number;
  // The voice-over's own lines, timed from the start of the video. Paste them
  // from captions/<script>.cues.json; seconds include the title card. Both sit
  // at the bottom: use these or the clips' own captions, not both at once.
  voiceCaptions?: { fromS: number; toS: number; text: string }[];
  intro?: Intro;
  outro?: Outro;
  // Behind a "contain" clip: a film narrower than the frame's aspect (1080 × 1920
  // in 886 × 1920) keeps its edges, and the bands match the films' night sea.
  letterbox?: string;
  accent?: string;       // the outro's figures; defaults to the films' route cyan
};

const CARD_S = 2;
const MUSIC_FADE_IN_S = 0.5;
const MUSIC_FADE_OUT_S = 1.5;

const FadeIn: React.FC<{ seconds: number; bg?: string; children: React.ReactNode }> = ({ seconds, bg, children }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const opacity = seconds > 0
    ? interpolate(frame, [0, seconds * fps], [0, 1], { extrapolateRight: "clamp" }) : 1;
  return <AbsoluteFill style={{ opacity, background: bg }}>{children}</AbsoluteFill>;
};

export const promoFrames = (p: PromoProps, fps: number) =>
  Math.max(1, Math.round(fps * (p.clips.reduce((s, c) => s + c.durationS, 0)
    + (p.title ? CARD_S : 0) + (p.intro?.durationS ?? 0) + (p.outro?.durationS ?? 0) + (p.endCard ? CARD_S : 0))));

const FONT = "-apple-system, 'PingFang TC', sans-serif";

const IntroBeat: React.FC<{ o: Intro }> = ({ o }) => {
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();
  const t = frame / fps;
  const zoomS = o.zoomS ?? 0.8;
  const aspect = o.screenAspect ?? 1206 / 2622;
  const screenW = width * 0.6, screenH = screenW / aspect;
  const bezel = width * 0.022, radius = width * 0.085;
  // Ease into the screen until it covers the frame, the way an app opens.
  const k = interpolate(t, [o.durationS - zoomS, o.durationS], [0, 1],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: (x) => x * x * (3 - 2 * x) });
  const intoTap = o.zoomInto === "tap" && o.tap;
  // Into the tap: an app icon is about a sixth of the screen's width; three times
  // that covers the frame.
  const cover = intoTap ? (width / (screenW * 0.16)) * 3 : Math.max(width / screenW, height / screenH) * 1.02;
  const scale = 1 + (cover - 1) * k;
  const origin = intoTap
    ? `${bezel + o.tap!.x * screenW}px ${bezel + o.tap!.y * screenH}px` : "50% 50%";
  const fadeOut = intoTap ? interpolate(t, [o.durationS - 0.2, o.durationS], [1, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" }) : 1;
  const rise = interpolate(t, [0, 0.6], [60, 0], { extrapolateRight: "clamp", easing: (x) => 1 - Math.pow(1 - x, 3) });
  const appear = interpolate(t, [0, 0.5], [0, 1], { extrapolateRight: "clamp" });
  const phoneY = height * 0.09;  // the phone sits below the title, and moves to centre as it zooms
  return (
    <AbsoluteFill style={{ background: "radial-gradient(ellipse at 50% 40%, #1a2733 0%, #0b0f14 70%)", overflow: "hidden" }}>
      {o.title ? (
        <div style={{
          position: "absolute", top: height * 0.07, width: "100%", textAlign: "center", color: "#f4efe6",
          fontFamily: FONT, fontWeight: 700, fontSize: width * 0.068, lineHeight: 1.3, whiteSpace: "pre-line",
          opacity: appear * Math.max(0, 1 - k * 3), transform: `translateY(${-k * 80}px)`,
        }}>{o.title}</div>
      ) : null}
      <AbsoluteFill style={{ justifyContent: "center", alignItems: "center" }}>
        <div style={{
          width: screenW + bezel * 2, height: screenH + bezel * 2, borderRadius: radius + bezel,
          background: "#050607", padding: bezel, boxSizing: "border-box", position: "relative",
          boxShadow: `0 0 0 ${width * 0.004}px #3a4047, 0 30px 80px rgba(0,0,0,0.6)`,
          opacity: appear * fadeOut, transformOrigin: origin,
          transform: `translateY(${(phoneY + rise) * (intoTap ? 1 : 1 - k)}px) scale(${scale})`,
        }}>
          <div style={{ width: screenW, height: screenH, borderRadius: radius, overflow: "hidden", position: "relative" }}>
            <OffthreadVideo src={staticFile(o.file)} muted startFrom={Math.round((o.fromS ?? 0) * fps)}
              style={{ width: "100%", height: "100%", objectFit: "cover" }} />
            {o.tap ? <TapRipple atS={o.tap.atS} x={o.tap.x * screenW} y={o.tap.y * screenH} size={screenW * 0.2} /> : null}
            {o.tap ? <Pointer atS={o.tap.atS} x={o.tap.x * screenW} y={(o.tap.y - 0.005) * screenH}
              size={screenW * 0.22} screenW={screenW} screenH={screenH} /> : null}
          </div>
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

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
  const sp = o.speed ?? 1;
  const statsAt = 0.35 / sp, step = 0.15 / sp;
  const headlineAt = statsAt + stats.length * step + 0.55 / sp, iconAt = headlineAt + 0.8 / sp;
  return (
    <AbsoluteFill style={{ background: "black", overflow: "hidden" }}>
      <Img src={staticFile(o.bg)} style={{
        width: "100%", height: "100%", objectFit: "cover",
        transform: `scale(${zoom})`, filter: `blur(${blur}px) brightness(${dim})`,
      }} />
      <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", fontFamily: FONT, color: "white" }}>
        <div style={{ display: "flex", gap: width * 0.07, marginBottom: width * 0.1 }}>
          {stats.map((s, i) => {
            const at = statsAt + i * step;
            const k = pop(at);
            const count = interpolate(t, [at, at + 0.9 / sp], [0, s.value],
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

const Caption: React.FC<{ text: string; at?: "top" | "bottom"; size?: number; inset?: { top?: number; bottom?: number } }> =
  ({ text, at = "bottom", size = 0.05, inset }) => {
  const frame = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();
  const y = interpolate(frame, [0, fps * 0.35], [20, 0], { extrapolateRight: "clamp" });
  const opacity = interpolate(frame, [0, fps * 0.35], [0, 1], { extrapolateRight: "clamp" });
  return (
    <AbsoluteFill style={at === "top"
      ? { justifyContent: "flex-start", alignItems: "center", paddingTop: height * (inset?.top ?? 0.08) }
      : { justifyContent: "flex-end", alignItems: "center", paddingBottom: height * (inset?.bottom ?? 0.09) }}>
      <div style={{
        opacity, transform: `translateY(${y}px)`, color: "white", fontSize: width * size,
        fontWeight: 600, fontFamily: "-apple-system, 'PingFang TC', sans-serif",
        background: "rgba(0,0,0,0.45)", borderRadius: width * 0.03,
        padding: `${width * 0.02}px ${width * 0.045}px`, textAlign: "center", maxWidth: "86%",
        textWrap: "balance", whiteSpace: "pre-line", lineHeight: 1.35,
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
  if (p.intro) {
    const len = Math.round(p.intro.durationS * fps);
    seq.push(<Sequence key="intro" from={at} durationInFrames={len}><IntroBeat o={p.intro} /></Sequence>);
    at += len;
  }
  p.clips.forEach((c, i) => {
    const len = Math.round(c.durationS * fps);
    seq.push(
      <Sequence key={`clip-${i}`} from={at} durationInFrames={len}>
        <FadeIn seconds={c.fadeS ?? p.fadeS ?? 0} bg={p.letterbox}>
          <OffthreadVideo
            src={staticFile(c.file)} muted playbackRate={c.rate ?? 1}
            startFrom={Math.round((c.fromS ?? 0) * fps)}
            style={{ width: "100%", height: "100%", objectFit: c.fit ?? "cover" }}
          />
        </FadeIn>
        {c.caption ? <Caption text={c.caption} at={c.captionAt ?? p.captionAt} size={p.captionSize} inset={p.captionInset} /> : null}
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
          <Caption text={c.text} at={p.captionAt} size={p.captionSize} inset={p.captionInset} />
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
