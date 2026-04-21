// MercHandlingPage.jsx — detailed mercenary management.
// Shows the merc's own loadout slots (they differ from the player's):
// Main Hand, Relic, Skins, Artifacts. Also contains a DNA research card
// that shows DNA study progress and navigates to the DNA page.

const MERC_SLOTS = [
  { id: 'mainhand',  label: 'Main Hand', icon: Icon.sword,   desc: 'Weapon issued to this mercenary.' },
  { id: 'relic',     label: 'Relic',     icon: Icon.crown,   desc: 'Relic bonded to this mercenary.' },
  { id: 'skins',     label: 'Skins',     icon: Icon.gem,     desc: 'Cosmetic skin applied to this mercenary.' },
  { id: 'artifacts', label: 'Artifacts', icon: Icon.diamond, desc: 'Set-bonus items this mercenary carries.' },
];

// Per-merc equipped loadout (stub data for the mockup).
const MERC_LOADOUTS = {
  pirate: {
    mainhand:  { name: 'Boarding Hook',     rarity: 2, dmg: 28 },
    relic:     { name: 'Drowned Coin',      rarity: 3, bonus: '+6% Luck' },
    skins:     null,
    artifacts: null,
  },
};

function MercHandlingPage({ mercId, onBack, onOpenDna }) {
  const merc = (window.MERCS || []).find(m => m.id === mercId) || (window.MERCS || [])[0];
  const loadout = MERC_LOADOUTS[mercId] || {};
  const [selectedSlot, setSelectedSlot] = React.useState('mainhand');
  const slotDef = MERC_SLOTS.find(s => s.id === selectedSlot);
  const item = loadout[selectedSlot];

  if (!merc) return null;

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
          <span style={{ fontSize: 11, letterSpacing: 3, color: THEME.textMute }}>MERCENARY</span>
          <span style={{ fontSize: 18, letterSpacing: 4, color: THEME.holoEdge, fontWeight: 600 }}>
            {merc.name.toUpperCase()}
          </span>
          <span style={{
            fontSize: 11, letterSpacing: 2, color: THEME.textDim,
            padding: '2px 7px', border: `1px solid ${THEME.holoDim}`,
          }}>LV {merc.level}</span>
        </div>
        <div style={{ flex: 1 }} />
        <div style={{
          display: 'flex', alignItems: 'center', gap: 5, padding: '6px 12px',
          border: `1px solid ${THEME.holoDim}`,
          background: 'rgba(10,24,44,0.72)',
          color: THEME.gold,
          fontFamily: 'Rajdhani, sans-serif', fontSize: 13, fontWeight: 700,
        }}>
          <Icon.gem width={13} height={13} />
          <span>1,280</span>
        </div>
      </div>

      {/* Loadout slots — same layout as Handling */}
      <div style={{
        position: 'absolute', left: 24, top: 90, width: 110,
        display: 'flex', flexDirection: 'column', gap: 20, zIndex: 3,
      }}>
        {[MERC_SLOTS[0], MERC_SLOTS[1]].map(def => (
          <HandlingSlot key={def.id} def={def} item={loadout[def.id]}
                        selected={selectedSlot === def.id}
                        onClick={() => setSelectedSlot(def.id)} />
        ))}
      </div>
      <div style={{
        position: 'absolute', right: 24, top: 90, width: 110,
        display: 'flex', flexDirection: 'column', gap: 20, zIndex: 3,
      }}>
        {[MERC_SLOTS[2], MERC_SLOTS[3]].map(def => (
          <HandlingSlot key={def.id} def={def} item={loadout[def.id]}
                        selected={selectedSlot === def.id}
                        onClick={() => setSelectedSlot(def.id)} />
        ))}
      </div>

      {/* Center character + side rings (reuse HandlingCharacterSlot styling) */}
      <div style={{
        position: 'absolute',
        left: 148, right: 148, top: 66, bottom: 240,
        zIndex: 2,
      }}>
        <MercModelSlot name={merc.name} />
      </div>

      {/* Bottom: detail (left) + DNA research card (right) */}
      <div style={{
        position: 'absolute',
        left: 148, right: 148, bottom: 24,
        display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14,
        zIndex: 3,
      }}>
        <HandlingDetailCard slot={slotDef} item={item} />
        <DnaResearchCard merc={merc} onOpen={onOpenDna} />
      </div>
    </div>
  );
}

function MercModelSlot({ name }) {
  return (
    <div style={{
      position: 'relative', width: '100%', height: '100%',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
    }}>
      <div style={{
        position: 'absolute', bottom: '8%', left: '50%',
        transform: 'translateX(-50%)',
        width: 240, height: 40,
        background: `radial-gradient(ellipse, ${THEME.holo} 0%, transparent 70%)`,
        opacity: 0.28, filter: 'blur(8px)',
      }} />
      <svg width="340" height="340" viewBox="0 0 340 340" style={{
        position: 'absolute',
        top: '50%', left: '50%', transform: 'translate(-50%, -52%)',
        opacity: 0.50,
      }}>
        <circle cx="170" cy="170" r="150" fill="none" stroke={THEME.holoSoft} strokeWidth="1" strokeDasharray="2 6" />
        <circle cx="170" cy="170" r="130" fill="none" stroke={THEME.holoDim} strokeWidth="1" />
        <g style={{ animation: 'dcRotate 60s linear infinite', transformOrigin: '170px 170px' }}>
          <circle cx="170" cy="170" r="160" fill="none" stroke={THEME.holoEdge} strokeWidth="0.7" strokeDasharray="1 24" />
        </g>
      </svg>
      <div style={{
        position: 'relative',
        width: 190, height: 300,
        display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
        border: `1px dashed ${THEME.holoSoft}`,
        background: 'rgba(15,35,65,0.15)',
      }}>
        <CornerLs size={12} color={THEME.holoEdge} thickness={2} />
        <Icon.character width={60} height={60} style={{ color: THEME.holoSoft, opacity: 0.6 }} />
        <div style={{
          marginTop: 18,
          fontFamily: 'Rajdhani, sans-serif', fontSize: 11, fontWeight: 600,
          letterSpacing: 2, color: THEME.holoEdge,
          textTransform: 'uppercase', textAlign: 'center',
        }}>{name} MODEL</div>
        <div style={{
          marginTop: 4,
          fontFamily: 'JetBrains Mono, monospace', fontSize: 9,
          color: THEME.textMute, textAlign: 'center',
        }}>ViewportFrame target</div>
      </div>
    </div>
  );
}

// DNA research card — sits in the bottom-right of MercHandling, replacing
// the generic "bonuses" card that Handling uses. Clicking opens the DNA page.
function DnaResearchCard({ merc, onOpen }) {
  const pct = Math.round((merc.dnaProgress || 0) * 100);
  const unlocked = Math.round((merc.dnaProgress || 0) * 16); // 16 fragments total
  return (
    <HoloFrame style={{ padding: 14, display: 'flex', flexDirection: 'column' }}>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 8, marginBottom: 10,
        paddingBottom: 8, borderBottom: `1px solid ${THEME.holoDim}`,
      }}>
        <Icon.dna width={13} height={13} style={{ color: THEME.holoEdge }} />
        <div style={{
          fontFamily: 'Rajdhani, sans-serif', fontSize: 14, fontWeight: 700,
          color: THEME.text, letterSpacing: 2, textTransform: 'uppercase',
        }}>DNA Research</div>
        <span style={{
          marginLeft: 'auto',
          fontFamily: 'Rajdhani, sans-serif', fontSize: 13, fontWeight: 700,
          color: THEME.holoEdge,
        }}>{pct}%</span>
      </div>

      {/* Mini-helix preview */}
      <div style={{
        display: 'flex', alignItems: 'center', gap: 14,
        marginBottom: 10,
      }}>
        <MiniHelix fill={merc.dnaProgress} />
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{
            fontSize: 11, color: THEME.textDim, lineHeight: 1.4,
            marginBottom: 6,
          }}>
            Fragments decoded: <span style={{ color: THEME.text, fontWeight: 600 }}>
              {unlocked}/16
            </span>
          </div>
          <HoloBar fill={merc.dnaProgress} height={5} segments={16} />
          <div style={{
            fontSize: 10, color: THEME.textMute, marginTop: 6, lineHeight: 1.4,
          }}>
            Hunt more {merc.name.toLowerCase()}s to decode additional DNA fragments.
          </div>
        </div>
      </div>

      <button className="menu-btn" onClick={onOpen} style={{
        marginTop: 'auto', padding: '9px 0',
        border: `1px solid ${THEME.holoEdge}`,
        background: 'rgba(40,90,150,0.40)',
        color: THEME.text,
        fontFamily: 'Rajdhani, sans-serif', fontSize: 13, fontWeight: 700,
        letterSpacing: 2, textTransform: 'uppercase',
        display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
        position: 'relative',
      }}>
        <CornerLs size={5} color={THEME.holoEdge} />
        <Icon.helix width={14} height={14} />
        <span>Study DNA</span>
        <Icon.chevR width={13} height={13} />
      </button>
    </HoloFrame>
  );
}

// Mini helix used as a thumbnail inside the DNA Research card.
// Two sinusoidal strands with rungs — fill% of rungs are lit.
function MiniHelix({ fill = 0, width = 66, height = 86 }) {
  const rungs = 10;
  const lit = Math.round(fill * rungs);
  const strandA = [];
  const strandB = [];
  for (let i = 0; i <= 40; i++) {
    const t = i / 40;
    const y = t * height;
    const x = width / 2 + Math.sin(t * Math.PI * 2.2) * (width * 0.34);
    const x2 = width / 2 - Math.sin(t * Math.PI * 2.2) * (width * 0.34);
    strandA.push(`${i === 0 ? 'M' : 'L'}${x.toFixed(1)} ${y.toFixed(1)}`);
    strandB.push(`${i === 0 ? 'M' : 'L'}${x2.toFixed(1)} ${y.toFixed(1)}`);
  }
  return (
    <svg width={width} height={height} viewBox={`0 0 ${width} ${height}`} style={{ flexShrink: 0 }}>
      <path d={strandA.join(' ')} fill="none" stroke={THEME.holoSoft} strokeWidth="1.5" strokeLinecap="round" />
      <path d={strandB.join(' ')} fill="none" stroke={THEME.holoSoft} strokeWidth="1.5" strokeLinecap="round" />
      {Array.from({ length: rungs }).map((_, i) => {
        const t = (i + 0.5) / rungs;
        const y = t * height;
        const x1 = width / 2 + Math.sin(t * Math.PI * 2.2) * (width * 0.34);
        const x2 = width / 2 - Math.sin(t * Math.PI * 2.2) * (width * 0.34);
        const on = i < lit;
        return (
          <line key={i} x1={x1} y1={y} x2={x2} y2={y}
                stroke={on ? THEME.holoEdge : THEME.holoDeep}
                strokeWidth={on ? 1.6 : 1}
                opacity={on ? 1 : 0.4}
                style={on ? { filter: `drop-shadow(0 0 3px ${THEME.holo})` } : {}} />
        );
      })}
    </svg>
  );
}

Object.assign(window, { MercHandlingPage, MiniHelix });
