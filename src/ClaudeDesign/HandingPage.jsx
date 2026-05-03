// HandlingPage.jsx — player's equipment screen (formerly "Arsenal/Equipment").
// Slots: Main Hand, Relic, Skins, Artifacts. Only 4 slots now.

const HANDLING_SLOTS = [
  { id: 'mainhand', label: 'Main Hand', icon: Icon.sword,   desc: 'Primary weapon carried into battle.' },
  { id: 'relic',    label: 'Relic',     icon: Icon.crown,   desc: 'Ancient artefact granting passive bonuses.' },
  { id: 'skins',    label: 'Skins',     icon: Icon.gem,     desc: 'Cosmetic appearance overrides.' },
  { id: 'artifacts',label: 'Artifacts', icon: Icon.diamond, desc: 'Set-bonus items from expeditions.' },
];

const HANDLING_EQUIPPED = {
  mainhand:  { name: 'Cutlass of Tides',  rarity: 3, dmg: 42 },
  relic:     { name: 'Saltborn Circlet',  rarity: 4, bonus: '+12% Mana' },
  skins:     null,
  artifacts: { name: 'Compass Fragment',  rarity: 3, bonus: '+8% Luck' },
};

function HandlingSlot({ def, item, selected, onClick }) {
  const empty = !item;
  const Icn = def.icon;
  return (
    <HoloFrame
      variant={selected ? 'active' : 'default'}
      glow={selected}
      className="menu-card"
      onClick={onClick}
      style={{
        width: 110, padding: 0,
        background: empty ? 'rgba(10,24,44,0.35)' : 'rgba(22,48,82,0.55)',
      }}
    >
      <div style={{
        width: 108, height: 108,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        borderBottom: `1px solid ${selected ? THEME.holoEdge : THEME.holoDim}`,
        color: empty ? THEME.textMute : THEME.holoEdge,
        position: 'relative',
      }}>
        <Icn width={44} height={44} />
        {item && (
          <div style={{
            position: 'absolute', bottom: 5, right: 6,
            fontFamily: 'Rajdhani, sans-serif',
            fontSize: 9, fontWeight: 700,
            color: THEME.gold,
            display: 'flex', gap: 1,
          }}>
            {Array.from({ length: item.rarity }).map((_, i) => (
              <Icon.star key={i} width={8} height={8} />
            ))}
          </div>
        )}
        {empty && (
          <Icon.plus width={14} height={14} style={{
            position: 'absolute', top: 6, right: 6,
            color: THEME.textMute,
          }} />
        )}
      </div>
      <div style={{
        padding: '6px 8px',
        fontFamily: 'Rajdhani, sans-serif', fontSize: 11, fontWeight: 600,
        letterSpacing: 1.5, textTransform: 'uppercase',
        textAlign: 'center',
        color: empty ? THEME.textMute : THEME.textDim,
      }}>
        {def.label}
      </div>
    </HoloFrame>
  );
}

function HandlingDetailCard({ slot, item }) {
  if (!item) {
    return (
      <HoloFrame variant="subtle" style={{ padding: 14 }}>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8,
        }}>
          <Icon.plus width={13} height={13} style={{ color: THEME.textDim }} />
          <div style={{
            fontFamily: 'Rajdhani, sans-serif', fontSize: 14, fontWeight: 700,
            color: THEME.textDim, letterSpacing: 2, textTransform: 'uppercase',
          }}>Empty · {slot.label}</div>
        </div>
        <div style={{ fontSize: 12, color: THEME.textMute, lineHeight: 1.5 }}>
          {slot.desc} Equip an item from your inventory to fill this slot.
        </div>
        <button className="menu-btn" style={{
          marginTop: 12, padding: '8px 12px', width: '100%',
          border: `1px solid ${THEME.holoDim}`,
          background: 'rgba(10,24,44,0.5)',
          color: THEME.text,
          fontFamily: 'Rajdhani, sans-serif', fontSize: 13, fontWeight: 600,
          letterSpacing: 2, textTransform: 'uppercase',
        }}>Open Inventory</button>
      </HoloFrame>
    );
  }
  return (
    <HoloFrame style={{ padding: 14 }}>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 10, marginBottom: 10,
      }}>
        <div style={{
          width: 38, height: 38,
          border: `1px solid ${THEME.holoEdge}`,
          background: 'rgba(15,35,65,0.5)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          color: THEME.holoEdge,
        }}>
          <slot.icon width={22} height={22} />
        </div>
        <div style={{ flex: 1 }}>
          <div style={{
            fontFamily: 'Rajdhani, sans-serif', fontSize: 15, fontWeight: 700,
            color: THEME.text, letterSpacing: 0.5,
          }}>{item.name}</div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 3 }}>
            <StarRow filled={item.rarity} total={5} size={9} />
            <span style={{ fontSize: 10, color: THEME.textDim, letterSpacing: 1 }}>
              {slot.label.toUpperCase()}
            </span>
          </div>
        </div>
      </div>
      <div style={{
        paddingTop: 10, borderTop: `1px solid ${THEME.holoDim}`,
        display: 'flex', flexDirection: 'column', gap: 5,
        fontSize: 11, color: THEME.textDim,
      }}>
        {item.dmg && <DetailRow icon={Icon.damage} label="Damage" val={`+${item.dmg}`} />}
        {item.def && <DetailRow icon={Icon.shield} label="Defense" val={`+${item.def}`} />}
        {item.uses && <DetailRow icon={Icon.flask} label="Uses" val={item.uses} />}
        {item.bonus && <DetailRow icon={Icon.spark} label="Bonus" val={item.bonus} />}
      </div>
    </HoloFrame>
  );
}
function DetailRow({ icon: IconComp, label, val }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
      <IconComp width={12} height={12} style={{ color: THEME.holoEdge }} />
      <span style={{ letterSpacing: 0.5 }}>{label}</span>
      <span style={{ flex: 1, borderBottom: `1px dashed ${THEME.holoDim}`, margin: '0 4px' }} />
      <span style={{ fontFamily: 'Rajdhani, sans-serif', fontWeight: 700, color: THEME.text }}>{val}</span>
    </div>
  );
}

function HandlingBonuses() {
  const bonuses = [
    { label: 'Total Damage', v: '+42', icon: Icon.damage },
    { label: 'Max Mana',     v: '+12%', icon: Icon.mana },
    { label: 'Luck',         v: '+8%',  icon: Icon.star },
    { label: 'Set Progress', v: '1/4',  icon: Icon.diamond },
  ];
  return (
    <HoloFrame style={{ padding: 14 }}>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 8, marginBottom: 10,
        paddingBottom: 8, borderBottom: `1px solid ${THEME.holoDim}`,
      }}>
        <Icon.spark width={13} height={13} style={{ color: THEME.holoEdge }} />
        <div style={{
          fontFamily: 'Rajdhani, sans-serif', fontSize: 14, fontWeight: 700,
          color: THEME.text, letterSpacing: 2, textTransform: 'uppercase',
        }}>Loadout Bonuses</div>
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        {bonuses.map(b => (
          <div key={b.label} style={{
            display: 'flex', alignItems: 'center', gap: 8,
            fontSize: 12, color: THEME.textDim,
          }}>
            <b.icon width={14} height={14} style={{ color: THEME.holoEdge }} />
            <span>{b.label}</span>
            <span style={{ flex: 1, borderBottom: `1px dashed ${THEME.holoDim}`, margin: '0 4px' }} />
            <span style={{
              fontFamily: 'Rajdhani, sans-serif', fontSize: 15, fontWeight: 700, color: THEME.gold,
            }}>{b.v}</span>
          </div>
        ))}
      </div>
    </HoloFrame>
  );
}

function HandlingCharacterSlot() {
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
        opacity: 0.25, filter: 'blur(8px)',
      }} />
      <svg width="340" height="340" viewBox="0 0 340 340" style={{
        position: 'absolute',
        top: '50%', left: '50%', transform: 'translate(-50%, -52%)',
        opacity: 0.45,
      }}>
        <circle cx="170" cy="170" r="150" fill="none" stroke={THEME.holoSoft} strokeWidth="1" strokeDasharray="2 6" />
        <circle cx="170" cy="170" r="130" fill="none" stroke={THEME.holoDim} strokeWidth="1" />
        <g style={{ animation: 'dcRotate 90s linear infinite', transformOrigin: '170px 170px' }}>
          <circle cx="170" cy="170" r="160" fill="none" stroke={THEME.holoEdge} strokeWidth="0.7" strokeDasharray="1 24" />
          {Array.from({ length: 8 }).map((_, i) => {
            const a = (i / 8) * Math.PI * 2;
            const x1 = 170 + Math.cos(a) * 155;
            const y1 = 170 + Math.sin(a) * 155;
            const x2 = 170 + Math.cos(a) * 165;
            const y2 = 170 + Math.sin(a) * 165;
            return <line key={i} x1={x1} y1={y1} x2={x2} y2={y2} stroke={THEME.holoEdge} strokeWidth="1" />;
          })}
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
        }}>PLAYER MODEL</div>
        <div style={{
          marginTop: 4,
          fontFamily: 'JetBrains Mono, monospace', fontSize: 9,
          color: THEME.textMute, textAlign: 'center',
        }}>ViewportFrame target</div>
      </div>
    </div>
  );
}

function HandlingPage({ onBack }) {
  const [selectedSlot, setSelectedSlot] = React.useState('mainhand');
  const slotDef = HANDLING_SLOTS.find(s => s.id === selectedSlot);
  const item = HANDLING_EQUIPPED[selectedSlot];

  return (
    <div style={{
      position: 'absolute', inset: 0,
      fontFamily: 'Inter, sans-serif',
      color: THEME.text,
    }}>
      {/* Top bar */}
      <div style={{
        position: 'absolute', top: 16, left: 16, right: 16,
        display: 'flex', alignItems: 'center', gap: 10, zIndex: 5,
      }}>
        <button className="menu-btn" onClick={onBack} style={{
          height: 34, padding: '0 14px',
          border: `1px solid ${THEME.holoSoft}`,
          background: 'rgba(10,24,44,0.72)',
          color: THEME.text,
          display: 'flex', alignItems: 'center', gap: 6,
          fontFamily: 'Rajdhani, sans-serif', fontSize: 13, fontWeight: 600,
          letterSpacing: 2, textTransform: 'uppercase',
        }}>
          <Icon.back width={14} height={14} />
          <span>Back</span>
        </button>
        <div style={{ flex: 1 }} />
        <div style={{
          fontFamily: 'Rajdhani, sans-serif', fontSize: 18, letterSpacing: 4,
          color: THEME.holoEdge, fontWeight: 600,
        }}>
          HANDLING
        </div>
        <div style={{ flex: 1 }} />
        <div style={{
          display: 'flex', alignItems: 'center', gap: 5, padding: '6px 12px',
          border: `1px solid ${THEME.holoDim}`,
          background: 'rgba(10,24,44,0.72)',
          color: THEME.gold,
          fontFamily: 'Rajdhani, sans-serif', fontSize: 13, fontWeight: 700,
        }}>
          <Icon.bag width={13} height={13} />
          <span>34 / 60</span>
        </div>
      </div>

      {/* 2 slots left (Main Hand, Relic) */}
      <div style={{
        position: 'absolute', left: 24, top: 90, width: 110,
        display: 'flex', flexDirection: 'column', gap: 20, zIndex: 3,
      }}>
        {[HANDLING_SLOTS[0], HANDLING_SLOTS[1]].map(def => (
          <HandlingSlot key={def.id} def={def} item={HANDLING_EQUIPPED[def.id]}
                        selected={selectedSlot === def.id}
                        onClick={() => setSelectedSlot(def.id)} />
        ))}
      </div>
      {/* 2 slots right (Skins, Artifacts) */}
      <div style={{
        position: 'absolute', right: 24, top: 90, width: 110,
        display: 'flex', flexDirection: 'column', gap: 20, zIndex: 3,
      }}>
        {[HANDLING_SLOTS[2], HANDLING_SLOTS[3]].map(def => (
          <HandlingSlot key={def.id} def={def} item={HANDLING_EQUIPPED[def.id]}
                        selected={selectedSlot === def.id}
                        onClick={() => setSelectedSlot(def.id)} />
        ))}
      </div>

      {/* Center character */}
      <div style={{
        position: 'absolute',
        left: 148, right: 148, top: 66, bottom: 240,
        zIndex: 2,
      }}>
        <HandlingCharacterSlot />
      </div>

      {/* Bottom cards: detail + bonuses */}
      <div style={{
        position: 'absolute',
        left: 148, right: 148, bottom: 24,
        display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14,
        zIndex: 3,
      }}>
        <HandlingDetailCard slot={slotDef} item={item} />
        <HandlingBonuses />
      </div>
    </div>
  );
}

Object.assign(window, { HandlingPage });
