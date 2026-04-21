// DnaPage.jsx — DNA study screen. Large helix in the center with 16
// segments; unlocked segments glow holo-cyan, locked segments are dim.
// A DNA sample slot on the left accepts a "sample" — dropping one
// advances decoding progress. Right panel lists decoded traits.

function DnaPage({ mercId, onBack }) {
  const mercs = window.MERCS || [];
  const merc = mercs.find(m => m.id === mercId) || mercs[0];
  const [progress, setProgress] = React.useState(merc ? merc.dnaProgress : 0);
  const [sampleIn, setSampleIn] = React.useState(false);
  const [decoding, setDecoding] = React.useState(false);

  if (!merc) return null;

  const totalSegs = 16;
  const decoded = Math.round(progress * totalSegs);

  const insertSample = () => {
    if (sampleIn || decoding) return;
    setSampleIn(true);
    setDecoding(true);
    // Simulate decoding — smoothly animate progress up by one segment.
    const start = progress;
    const target = Math.min(1, progress + 1 / totalSegs);
    const t0 = performance.now();
    const step = (t) => {
      const k = Math.min(1, (t - t0) / 1400);
      const eased = 1 - Math.pow(1 - k, 3);
      setProgress(start + (target - start) * eased);
      if (k < 1) requestAnimationFrame(step);
      else { setDecoding(false); setSampleIn(false); }
    };
    requestAnimationFrame(step);
  };

  return (
    <div style={{
      position: 'absolute', inset: 0,
      fontFamily: 'Inter, sans-serif', color: THEME.text,
    }}>
      {/* Top bar */}
      <div style={{
        position: 'absolute', top: 16, left: 16, right: 16,
        display: 'flex', alignItems: 'center', gap: 10, zIndex: 5,
      }}>
        <button className="menu-btn" onClick={onBack} style={{
          height: 34, padding: '0 14px',
          border: `1px solid ${THEME.holoSoft}`,
          background: 'rgba(10,24,44,0.72)', color: THEME.text,
          display: 'flex', alignItems: 'center', gap: 6,
          fontFamily: 'Rajdhani, sans-serif', fontSize: 13, fontWeight: 600,
          letterSpacing: 2, textTransform: 'uppercase',
        }}>
          <Icon.back width={14} height={14} /><span>Back</span>
        </button>
        <div style={{ flex: 1 }} />
        <div style={{
          display: 'flex', alignItems: 'baseline', gap: 10,
          fontFamily: 'Rajdhani, sans-serif',
        }}>
          <span style={{ fontSize: 11, letterSpacing: 3, color: THEME.textMute }}>DNA · STUDY</span>
          <span style={{ fontSize: 18, letterSpacing: 4, color: THEME.holoEdge, fontWeight: 600 }}>
            {merc.name.toUpperCase()}
          </span>
        </div>
        <div style={{ flex: 1 }} />
        <div style={{
          display: 'flex', alignItems: 'center', gap: 5, padding: '6px 12px',
          border: `1px solid ${THEME.holoDim}`,
          background: 'rgba(10,24,44,0.72)',
          color: THEME.holoEdge,
          fontFamily: 'Rajdhani, sans-serif', fontSize: 13, fontWeight: 700,
        }}>
          <Icon.vial width={13} height={13} />
          <span>SAMPLES · 3</span>
        </div>
      </div>

      {/* LEFT: sample slot */}
      <div style={{
        position: 'absolute', left: 24, top: 70, bottom: 24, width: 260,
        display: 'flex', flexDirection: 'column', gap: 14, zIndex: 3,
      }}>
        <SampleSlot active={sampleIn} decoding={decoding} onInsert={insertSample} />
        <ResearchMeta merc={merc} decoded={decoded} total={totalSegs} />
      </div>

      {/* CENTER: big helix */}
      <div style={{
        position: 'absolute', left: 300, right: 320, top: 70, bottom: 24,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        zIndex: 2,
      }}>
        <BigHelix progress={progress} decoding={decoding} />
      </div>

      {/* RIGHT: decoded traits */}
      <div style={{
        position: 'absolute', right: 24, top: 70, bottom: 24, width: 300,
        zIndex: 3,
      }}>
        <DecodedTraits progress={progress} />
      </div>
    </div>
  );
}

function SampleSlot({ active, decoding, onInsert }) {
  return (
    <HoloFrame style={{ padding: 14, display: 'flex', flexDirection: 'column' }}>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 8, marginBottom: 12,
        paddingBottom: 10, borderBottom: `1px solid ${THEME.holoDim}`,
      }}>
        <Icon.vial width={13} height={13} style={{ color: THEME.holoEdge }} />
        <div style={{
          fontFamily: 'Rajdhani, sans-serif', fontSize: 14, fontWeight: 700,
          color: THEME.text, letterSpacing: 2, textTransform: 'uppercase',
        }}>Sample Slot</div>
      </div>

      {/* The slot itself — a hex outline with corner Ls */}
      <div
        onClick={onInsert}
        className="menu-card"
        style={{
          position: 'relative',
          height: 150,
          border: `1px dashed ${active ? THEME.holoEdge : THEME.holoSoft}`,
          background: active
            ? `radial-gradient(ellipse at center, ${THEME.holoDeep} 0%, rgba(10,24,44,0.6) 80%)`
            : 'rgba(10,24,44,0.35)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          cursor: decoding ? 'wait' : 'pointer',
          overflow: 'hidden',
        }}
      >
        <CornerLs size={10} color={active ? THEME.holoEdge : THEME.holoSoft} thickness={2} />
        {/* Idle: placeholder vial icon + text. Active: glowing vial + scan line. */}
        <div style={{
          display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8,
          color: active ? THEME.holoEdge : THEME.textDim,
          transition: 'all .3s ease',
        }}>
          <Icon.vial width={44} height={44} style={{
            filter: active ? `drop-shadow(0 0 8px ${THEME.holo})` : 'none',
          }} />
          <div style={{
            fontFamily: 'Rajdhani, sans-serif', fontSize: 11, fontWeight: 600,
            letterSpacing: 2, textTransform: 'uppercase', textAlign: 'center',
          }}>
            {decoding ? 'Decoding…' : active ? 'Sample loaded' : 'Drop DNA sample'}
          </div>
        </div>
        {active && (
          <div style={{
            position: 'absolute', left: 0, right: 0, height: 2,
            background: `linear-gradient(90deg, transparent, ${THEME.holoEdge}, transparent)`,
            animation: 'dcScan 1.4s linear infinite',
            boxShadow: `0 0 8px ${THEME.holo}`,
          }} />
        )}
      </div>

      <div style={{
        marginTop: 10, fontSize: 11, color: THEME.textMute,
        lineHeight: 1.5, textAlign: 'center',
      }}>
        Click the slot to insert a DNA sample. Each decode unlocks one fragment.
      </div>
    </HoloFrame>
  );
}

function ResearchMeta({ merc, decoded, total }) {
  return (
    <HoloFrame style={{ padding: 14, flex: 1 }}>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 8, marginBottom: 12,
        paddingBottom: 10, borderBottom: `1px solid ${THEME.holoDim}`,
      }}>
        <Icon.diamond width={13} height={13} style={{ color: THEME.holoEdge }} />
        <div style={{
          fontFamily: 'Rajdhani, sans-serif', fontSize: 14, fontWeight: 700,
          color: THEME.text, letterSpacing: 2, textTransform: 'uppercase',
        }}>Research Log</div>
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8, fontSize: 12, color: THEME.textDim }}>
        <MetaRow label="Subject"     value={merc.name} />
        <MetaRow label="Class"       value={merc.role.split('·')[0].trim()} />
        <MetaRow label="Fragments"   value={`${decoded} / ${total}`} highlight />
        <MetaRow label="Integrity"   value={decoded >= total ? 'COMPLETE' : 'PARTIAL'} />
        <MetaRow label="Kills Logged" value={Math.max(1, decoded * 2 + 1)} />
      </div>
    </HoloFrame>
  );
}
function MetaRow({ label, value, highlight }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
      <span style={{ letterSpacing: 1.2, textTransform: 'uppercase', fontSize: 10 }}>{label}</span>
      <span style={{ flex: 1, borderBottom: `1px dashed ${THEME.holoDim}`, margin: '0 4px' }} />
      <span style={{
        fontFamily: 'Rajdhani, sans-serif', fontSize: 13, fontWeight: 700,
        color: highlight ? THEME.holoEdge : THEME.text,
      }}>{value}</span>
    </div>
  );
}

// Large helix — two strands + 16 rungs (decoded light, rest dark).
function BigHelix({ progress, decoding }) {
  const w = 280, h = 440;
  const rungs = 16;
  const lit = Math.round(progress * rungs);

  // Strand geometry
  const pathFor = (phase) => {
    const pts = [];
    const N = 80;
    for (let i = 0; i <= N; i++) {
      const t = i / N;
      const y = t * h;
      const x = w / 2 + Math.sin(t * Math.PI * 3 + phase) * (w * 0.32);
      pts.push(`${i === 0 ? 'M' : 'L'}${x.toFixed(2)} ${y.toFixed(2)}`);
    }
    return pts.join(' ');
  };

  const rungPositions = Array.from({ length: rungs }).map((_, i) => {
    const t = (i + 0.5) / rungs;
    const y = t * h;
    const x1 = w / 2 + Math.sin(t * Math.PI * 3) * (w * 0.32);
    const x2 = w / 2 + Math.sin(t * Math.PI * 3 + Math.PI) * (w * 0.32);
    return { y, x1, x2, t };
  });

  return (
    <div style={{ position: 'relative', width: w + 60, height: h + 40 }}>
      {/* Ambient rings behind helix */}
      <svg width={w + 60} height={h + 40} style={{ position: 'absolute', inset: 0, opacity: 0.35 }}>
        <g style={{ animation: 'dcRotate 80s linear infinite', transformOrigin: `${(w + 60) / 2}px ${(h + 40) / 2}px` }}>
          <circle cx={(w + 60) / 2} cy={(h + 40) / 2} r={Math.min(w, h) * 0.52} fill="none"
                  stroke={THEME.holoDim} strokeWidth="1" strokeDasharray="1 14" />
        </g>
        <circle cx={(w + 60) / 2} cy={(h + 40) / 2} r={Math.min(w, h) * 0.42} fill="none"
                stroke={THEME.holoDim} strokeWidth="1" strokeDasharray="2 8" />
      </svg>

      <svg width={w} height={h} viewBox={`0 0 ${w} ${h}`} style={{
        position: 'absolute', left: 30, top: 20,
      }}>
        <defs>
          <linearGradient id="strandGrad" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%"   stopColor={THEME.holoEdge} stopOpacity="0.9" />
            <stop offset="50%"  stopColor={THEME.holo}     stopOpacity="0.7" />
            <stop offset="100%" stopColor={THEME.holoEdge} stopOpacity="0.9" />
          </linearGradient>
        </defs>
        {/* Backbones */}
        <path d={pathFor(0)} fill="none" stroke="url(#strandGrad)" strokeWidth="2.2" strokeLinecap="round" />
        <path d={pathFor(Math.PI)} fill="none" stroke="url(#strandGrad)" strokeWidth="2.2" strokeLinecap="round" />
        {/* Rungs */}
        {rungPositions.map((r, i) => {
          const on = i < lit;
          const [minX, maxX] = r.x1 < r.x2 ? [r.x1, r.x2] : [r.x2, r.x1];
          return (
            <g key={i}>
              <line x1={minX} y1={r.y} x2={maxX} y2={r.y}
                    stroke={on ? THEME.holoEdge : THEME.holoDeep}
                    strokeWidth={on ? 2.3 : 1.2}
                    opacity={on ? 1 : 0.35}
                    style={on ? { filter: `drop-shadow(0 0 6px ${THEME.holo})` } : {}} />
              {/* Nucleotide nodes */}
              <circle cx={r.x1} cy={r.y} r={on ? 3.5 : 2.5}
                      fill={on ? THEME.holoEdge : THEME.holoDeep}
                      opacity={on ? 1 : 0.5}
                      style={on ? { filter: `drop-shadow(0 0 4px ${THEME.holo})` } : {}} />
              <circle cx={r.x2} cy={r.y} r={on ? 3.5 : 2.5}
                      fill={on ? THEME.holoEdge : THEME.holoDeep}
                      opacity={on ? 1 : 0.5}
                      style={on ? { filter: `drop-shadow(0 0 4px ${THEME.holo})` } : {}} />
              {/* Fragment index label for lit rungs */}
              {on && (
                <text x={(r.x1 + r.x2) / 2} y={r.y - 5}
                      fontFamily="JetBrains Mono, monospace" fontSize="7"
                      fill={THEME.holoEdge} textAnchor="middle" opacity="0.7">
                  F{String(i + 1).padStart(2, '0')}
                </text>
              )}
            </g>
          );
        })}
      </svg>

      {/* Progress ticker beneath helix */}
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 0,
        display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 10,
        fontFamily: 'Rajdhani, sans-serif',
      }}>
        <span style={{ fontSize: 11, letterSpacing: 3, color: THEME.textMute, textTransform: 'uppercase' }}>
          Genome Decoded
        </span>
        <span style={{ fontSize: 18, fontWeight: 700, color: THEME.holoEdge, letterSpacing: 1 }}>
          {Math.round(progress * 100)}%
        </span>
        {decoding && (
          <span style={{
            fontSize: 10, letterSpacing: 2, color: THEME.holoEdge,
            textTransform: 'uppercase', animation: 'dcPulse 1s ease-in-out infinite',
          }}>· Scanning</span>
        )}
      </div>
    </div>
  );
}

// Decoded traits panel — unlocks at specific thresholds.
function DecodedTraits({ progress }) {
  const traits = [
    { at: 0.00, icon: Icon.character, name: 'Species',      val: 'Humanoid · Pirate lineage' },
    { at: 0.10, icon: Icon.strength,  name: 'Base Strength', val: 'Above average' },
    { at: 0.25, icon: Icon.mutation,  name: 'Mobility',      val: 'Agile, coastal' },
    { at: 0.40, icon: Icon.mask,      name: 'Behaviour',     val: 'Aggressive, grouping' },
    { at: 0.55, icon: Icon.spark,     name: 'Ability Seed',  val: 'Iron Grip unlocked' },
    { at: 0.70, icon: Icon.helix,     name: 'Rare Marker',   val: '???' },
    { at: 0.85, icon: Icon.star,      name: 'Mutation',      val: '???' },
    { at: 1.00, icon: Icon.crown,     name: 'Full Genome',   val: '???' },
  ];

  return (
    <HoloFrame style={{ padding: 14, display: 'flex', flexDirection: 'column', height: '100%' }}>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 8, marginBottom: 12,
        paddingBottom: 10, borderBottom: `1px solid ${THEME.holoDim}`,
      }}>
        <Icon.dna width={13} height={13} style={{ color: THEME.holoEdge }} />
        <div style={{
          fontFamily: 'Rajdhani, sans-serif', fontSize: 14, fontWeight: 700,
          color: THEME.text, letterSpacing: 2, textTransform: 'uppercase',
        }}>Decoded Traits</div>
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8, flex: 1, overflow: 'auto' }}>
        {traits.map((t, i) => {
          const unlocked = progress >= t.at;
          const Icn = t.icon;
          return (
            <div key={i} style={{
              display: 'flex', gap: 10, alignItems: 'center',
              padding: '8px 10px',
              background: unlocked ? 'rgba(22,48,82,0.40)' : 'rgba(10,24,44,0.40)',
              border: `1px solid ${unlocked ? THEME.holoSoft : THEME.holoDim}`,
              opacity: unlocked ? 1 : 0.55,
              position: 'relative',
            }}>
              <CornerLs size={4} color={unlocked ? THEME.holoEdge : THEME.holoDim} />
              <div style={{
                width: 26, height: 26, flexShrink: 0,
                border: `1px solid ${unlocked ? THEME.holoEdge : THEME.holoDim}`,
                background: 'rgba(10,24,44,0.7)',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                color: unlocked ? THEME.holoEdge : THEME.textMute,
              }}>
                {unlocked ? <Icn width={14} height={14} /> : <Icon.lock width={11} height={11} />}
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{
                  fontFamily: 'Rajdhani, sans-serif', fontSize: 12, fontWeight: 700,
                  color: unlocked ? THEME.text : THEME.textDim,
                  letterSpacing: 1, textTransform: 'uppercase',
                }}>{t.name}</div>
                <div style={{ fontSize: 11, color: THEME.textDim, marginTop: 1, lineHeight: 1.3 }}>
                  {unlocked ? t.val : `Decodes at ${Math.round(t.at * 100)}%`}
                </div>
              </div>
            </div>
          );
        })}
      </div>
    </HoloFrame>
  );
}

Object.assign(window, { DnaPage });
