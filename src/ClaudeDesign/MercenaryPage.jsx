// MercenaryPage.jsx — list on the left, character slot in the center,
// selected merc's level/XP/stats/abilities + MANAGE button on the right.

const MERCS = [
  { id: 'pirate',   name: 'Pirate',   rarity: 2, level: 7,  xp: 320, xpMax: 500, locked: false, hired: true,  price: null, role: 'Sailor · Melee',  dnaProgress: 0.62 },
  { id: 'gunner',   name: 'Gunner',   rarity: 3, level: 4,  xp: 120, xpMax: 450, locked: false, hired: false, price: 120,  role: 'Ranged · Crew',   dnaProgress: 0.28 },
  { id: 'swabbie',  name: 'Swabbie',  rarity: 1, level: 2,  xp: 40,  xpMax: 200, locked: false, hired: false, price: 40,   role: 'Support · Crew',  dnaProgress: 0.12 },
  { id: 'navigator',name: 'Navigator',rarity: 3, level: 5,  xp: 200, xpMax: 500, locked: false, hired: false, price: 200,  role: 'Scout · Utility', dnaProgress: 0.45 },
  { id: 'quartermaster', name: 'Quartermaster', rarity: 4, level: 0, xp: 0, xpMax: 600, locked: true,  hired: false, price: null, role: 'Locked · Lv 10', dnaProgress: 0 },
  { id: 'captain',  name: 'Captain',  rarity: 5, level: 0,  xp: 0,   xpMax: 800, locked: true,  hired: false, price: null, role: 'Locked · Lv 20', dnaProgress: 0 },
];
window.MERCS = MERCS;

function MercCard({ merc, selected, onClick }) {
  return (
    <HoloFrame
      variant={selected ? 'active' : 'default'}
      glow={selected}
      className="menu-card"
      onClick={onClick}
      style={{
        padding: 10,
        display: 'flex', alignItems: 'center', gap: 10,
        opacity: merc.locked ? 0.55 : 1,
      }}
    >
      {/* Portrait slot */}
      <div style={{
        width: 52, height: 52, flexShrink: 0,
        background: 'rgba(15,35,65,0.35)',
        border: `1px solid ${selected ? THEME.holoEdge : THEME.holoDim}`,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        position: 'relative',
      }}>
        <CornerLs size={5} color={selected ? THEME.holoEdge : THEME.holoSoft} />
        {merc.locked
          ? <Icon.lock width={20} height={20} style={{ color: THEME.textMute }} />
          : <Icon.character width={28} height={28} style={{ color: THEME.holoSoft }} />}
        {/* Level badge in corner */}
        {!merc.locked && merc.hired && (
          <div style={{
            position: 'absolute', bottom: -5, right: -5,
            minWidth: 22, height: 18, padding: '0 4px',
            background: THEME.bgA, border: `1px solid ${THEME.holoEdge}`,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            fontFamily: 'Rajdhani, sans-serif', fontSize: 11, fontWeight: 700,
            color: THEME.holoEdge, letterSpacing: 0.5,
          }}>{merc.level}</div>
        )}
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          display: 'flex', alignItems: 'baseline', gap: 6, marginBottom: 3,
        }}>
          <div style={{
            fontFamily: 'Rajdhani, sans-serif', fontSize: 15, fontWeight: 700,
            color: THEME.text, letterSpacing: 0.5,
          }}>{merc.name}</div>
          {merc.hired && (
            <span style={{
              fontSize: 8, letterSpacing: 1.5, color: THEME.success,
              fontFamily: 'Rajdhani, sans-serif', fontWeight: 700,
              border: `1px solid ${THEME.success}`, padding: '1px 4px',
            }}>OWNED</span>
          )}
        </div>
        <StarRow filled={merc.rarity} total={5} size={9} />
        <div style={{ fontSize: 10, color: THEME.textDim, marginTop: 3, letterSpacing: 0.3 }}>
          {merc.role}
        </div>
      </div>
      {merc.price != null && !merc.hired && (
        <div style={{
          display: 'flex', alignItems: 'center', gap: 3,
          fontFamily: 'Rajdhani, sans-serif', fontSize: 13, fontWeight: 700,
          color: THEME.gold,
        }}>
          <Icon.gem width={12} height={12} />
          <span>{merc.price}</span>
        </div>
      )}
    </HoloFrame>
  );
}

function MercList({ selectedId, onSelect }) {
  return (
    <HoloFrame style={{ padding: 12, display: 'flex', flexDirection: 'column', height: '100%' }}>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 8, marginBottom: 12,
        paddingBottom: 10, borderBottom: `1px solid ${THEME.holoDim}`,
      }}>
        <Icon.users width={14} height={14} style={{ color: THEME.holoEdge }} />
        <div style={{
          fontFamily: 'Rajdhani, sans-serif', fontSize: 15, fontWeight: 700,
          color: THEME.text, letterSpacing: 2, textTransform: 'uppercase',
        }}>Mercenaries</div>
        <span style={{
          marginLeft: 'auto', fontSize: 11, color: THEME.textDim, fontFamily: 'Rajdhani, sans-serif',
        }}>1 / 6 HIRED</span>
      </div>
      <div style={{
        flex: 1, display: 'flex', flexDirection: 'column', gap: 8,
        overflow: 'auto',
      }}>
        {MERCS.map(m => (
          <MercCard key={m.id} merc={m} selected={selectedId === m.id} onClick={() => onSelect(m.id)} />
        ))}
      </div>
    </HoloFrame>
  );
}

// ─── Top meta bar (name, class, rarity, hire/owned) ───────────────────
function CharMetaBar({ merc }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 12,
      padding: '10px 14px',
      background: 'rgba(10,24,44,0.72)',
      border: `1px solid ${THEME.holoSoft}`,
      position: 'relative',
    }}>
      <CornerLs size={6} color={THEME.holoEdge} />
      <div style={{
        fontFamily: 'Rajdhani, sans-serif', fontSize: 26, fontWeight: 700,
        color: THEME.text, letterSpacing: 1,
      }}>
        {merc.name}
      </div>
      <div style={{ width: 1, height: 24, background: THEME.holoDim }} />
      <div>
        <div style={{ fontSize: 9, letterSpacing: 1.5, color: THEME.textMute }}>RARITY</div>
        <StarRow filled={merc.rarity} total={5} size={11} />
      </div>
      <div style={{ width: 1, height: 24, background: THEME.holoDim }} />
      <div>
        <div style={{ fontSize: 9, letterSpacing: 1.5, color: THEME.textMute }}>CLASS</div>
        <div style={{
          fontFamily: 'Rajdhani, sans-serif', fontSize: 13, fontWeight: 600, color: THEME.text,
        }}>{merc.role}</div>
      </div>
      <div style={{ flex: 1 }} />
      {merc.hired ? (
        <span style={{
          fontSize: 10, letterSpacing: 2, color: THEME.success,
          fontFamily: 'Rajdhani, sans-serif', fontWeight: 700,
          border: `1px solid ${THEME.success}`, padding: '3px 8px',
        }}>OWNED</span>
      ) : (
        <button className="menu-btn" style={{
          padding: '6px 14px',
          border: `1px solid ${THEME.gold}`,
          background: 'rgba(180,120,40,0.18)',
          color: THEME.gold,
          fontFamily: 'Rajdhani, sans-serif', fontSize: 13, fontWeight: 700,
          letterSpacing: 2, textTransform: 'uppercase',
          display: 'flex', alignItems: 'center', gap: 6,
        }}>
          <Icon.gem width={12} height={12} />
          <span>Hire · {merc.price}</span>
        </button>
      )}
    </div>
  );
}

// ─── Level + XP card (top of right column) ────────────────────────────
function LevelXPBlock({ merc }) {
  const fill = merc.xpMax ? merc.xp / merc.xpMax : 0;
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 12,
      marginBottom: 14, paddingBottom: 12,
      borderBottom: `1px solid ${THEME.holoDim}`,
    }}>
      {/* Big LVL badge */}
      <div style={{
        width: 56, height: 56, flexShrink: 0,
        border: `1px solid ${THEME.holoEdge}`,
        background: `linear-gradient(135deg, ${THEME.holoDeep} 0%, transparent 80%)`,
        display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
        position: 'relative',
      }}>
        <CornerLs size={5} color={THEME.holoEdge} />
        <div style={{
          fontSize: 9, letterSpacing: 2, color: THEME.holoEdge,
          fontFamily: 'Rajdhani, sans-serif', fontWeight: 600, lineHeight: 1,
        }}>LVL</div>
        <div style={{
          fontFamily: 'Rajdhani, sans-serif', fontSize: 26, fontWeight: 700,
          lineHeight: 1, color: THEME.text, marginTop: 2,
        }}>{merc.level}</div>
      </div>
      {/* XP bar + numbers */}
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          display: 'flex', justifyContent: 'space-between', alignItems: 'baseline',
          marginBottom: 5,
        }}>
          <div style={{
            display: 'flex', alignItems: 'center', gap: 5,
            color: THEME.holoEdge,
          }}>
            <Icon.xp width={12} height={12} />
            <span style={{
              fontSize: 10, letterSpacing: 1.5, fontWeight: 600,
              fontFamily: 'Inter, sans-serif', textTransform: 'uppercase',
            }}>Experience</span>
          </div>
          <div style={{
            fontFamily: 'Rajdhani, sans-serif', fontSize: 12, fontWeight: 500,
            color: THEME.textDim,
          }}>
            <span style={{ color: THEME.text }}>{merc.xp}</span> / {merc.xpMax}
          </div>
        </div>
        <HoloBar fill={fill} height={7} segments={10} />
        <div style={{
          marginTop: 4, fontSize: 10, color: THEME.textMute,
          fontFamily: 'Inter, sans-serif', letterSpacing: 0.3,
        }}>
          {Math.round((1 - fill) * merc.xpMax)} XP to next level
        </div>
      </div>
    </div>
  );
}

function CharStat({ icon: IconComp, label, value, maxValue = 100 }) {
  return (
    <div>
      <div style={{
        display: 'flex', justifyContent: 'space-between', alignItems: 'center',
        marginBottom: 5,
      }}>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 6,
          color: THEME.holoEdge,
        }}>
          <IconComp width={14} height={14} />
          <span style={{
            fontFamily: 'Inter, sans-serif', fontSize: 10, fontWeight: 500,
            letterSpacing: 1.5, color: THEME.textDim, textTransform: 'uppercase',
          }}>{label}</span>
        </div>
        <span style={{
          fontFamily: 'Rajdhani, sans-serif', fontSize: 15, fontWeight: 700, color: THEME.text,
        }}>{value}</span>
      </div>
      <HoloBar fill={value / maxValue} height={5} />
    </div>
  );
}

function AbilityRow({ name, desc, unlocked }) {
  return (
    <div style={{
      display: 'flex', gap: 10, alignItems: 'flex-start',
      padding: 10,
      background: unlocked ? 'rgba(22,48,82,0.40)' : 'rgba(10,24,44,0.40)',
      border: `1px solid ${unlocked ? THEME.holoSoft : THEME.holoDim}`,
      opacity: unlocked ? 1 : 0.6,
      position: 'relative',
    }}>
      <CornerLs size={4} color={unlocked ? THEME.holoEdge : THEME.holoDim} />
      <div style={{
        width: 30, height: 30, flexShrink: 0,
        border: `1px solid ${unlocked ? THEME.holoEdge : THEME.holoDim}`,
        background: 'rgba(10,24,44,0.7)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        color: unlocked ? THEME.holoEdge : THEME.textMute,
      }}>
        {unlocked ? <Icon.spark width={15} height={15} /> : <Icon.lock width={13} height={13} />}
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          fontFamily: 'Rajdhani, sans-serif', fontSize: 13, fontWeight: 700,
          color: unlocked ? THEME.text : THEME.textDim,
          letterSpacing: 0.5,
        }}>{name}</div>
        <div style={{ fontSize: 11, color: THEME.textDim, marginTop: 2, lineHeight: 1.4 }}>
          {desc}
        </div>
      </div>
    </div>
  );
}

// ─── Right-side panel — XP, stats, abilities, MANAGE ──────────────────
function MercCharacteristics({ merc, onManage }) {
  // Per-merc stat distribution (Strength, Speed, Luck). Scaled to 100.
  const STATS = {
    pirate:    { str: 72, spd: 48, luck: 35 },
    gunner:    { str: 55, spd: 70, luck: 40 },
    swabbie:   { str: 30, spd: 40, luck: 25 },
    navigator: { str: 40, spd: 80, luck: 75 },
    quartermaster: { str: 65, spd: 55, luck: 50 },
    captain:   { str: 90, spd: 80, luck: 85 },
  }[merc.id] || { str: 0, spd: 0, luck: 0 };

  return (
    <HoloFrame style={{ padding: 14, display: 'flex', flexDirection: 'column', gap: 14, height: '100%' }}>
      {/* Top: Level + XP */}
      <LevelXPBlock merc={merc} />

      {/* Characteristics */}
      <div>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 8, marginBottom: 12,
          paddingBottom: 10, borderBottom: `1px solid ${THEME.holoDim}`,
        }}>
          <Icon.diamond width={13} height={13} style={{ color: THEME.holoEdge }} />
          <div style={{
            fontFamily: 'Rajdhani, sans-serif', fontSize: 14, fontWeight: 700,
            color: THEME.text, letterSpacing: 2, textTransform: 'uppercase',
          }}>Characteristics</div>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          <CharStat icon={Icon.strength} label="Strength" value={STATS.str} />
          <CharStat icon={Icon.mutation} label="Speed"    value={STATS.spd} />
          <CharStat icon={Icon.star}     label="Luck"     value={STATS.luck} />
        </div>
      </div>

      {/* Abilities */}
      <div>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 8, marginBottom: 10,
          paddingBottom: 8, borderBottom: `1px solid ${THEME.holoDim}`,
        }}>
          <Icon.spark width={13} height={13} style={{ color: THEME.holoEdge }} />
          <div style={{
            fontFamily: 'Rajdhani, sans-serif', fontSize: 14, fontWeight: 700,
            color: THEME.text, letterSpacing: 2, textTransform: 'uppercase',
          }}>Abilities</div>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          <AbilityRow name="Iron Grip"   desc="+15% melee damage while boarding." unlocked />
          <AbilityRow name="Plunder"     desc="Chance to double loot drops." unlocked={merc.rarity >= 3} />
          <AbilityRow name="Sea Veteran" desc="Reduces stamina cost on long voyages." unlocked={merc.rarity >= 4} />
        </div>
      </div>

      <div style={{ flex: 1 }} />

      {/* MANAGE button — only enabled if hired */}
      <button
        className="menu-btn"
        onClick={merc.hired ? onManage : undefined}
        disabled={!merc.hired}
        style={{
          padding: '12px 0',
          border: `1px solid ${merc.hired ? THEME.holoEdge : THEME.holoDim}`,
          background: merc.hired ? 'rgba(40,90,150,0.55)' : 'rgba(10,24,44,0.40)',
          color: merc.hired ? THEME.text : THEME.textMute,
          fontFamily: 'Rajdhani, sans-serif', fontSize: 14, fontWeight: 700,
          letterSpacing: 3, textTransform: 'uppercase',
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
          cursor: merc.hired ? 'pointer' : 'not-allowed',
          position: 'relative',
          boxShadow: merc.hired ? `0 0 18px -4px ${THEME.holo}` : 'none',
        }}
      >
        <CornerLs size={6} color={merc.hired ? THEME.holoEdge : THEME.holoDim} />
        <Icon.diamond width={14} height={14} />
        <span>Manage</span>
        <Icon.chevR width={14} height={14} />
      </button>
    </HoloFrame>
  );
}

function MercCharacterSlot({ merc, onHandling }) {
  return (
    <div style={{
      position: 'relative', width: '100%', height: '100%',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
    }}>
      <div style={{
        position: 'absolute', bottom: '8%', left: '50%',
        transform: 'translateX(-50%)',
        width: 260, height: 44,
        background: `radial-gradient(ellipse, ${THEME.holo} 0%, transparent 70%)`,
        opacity: 0.28, filter: 'blur(8px)',
      }} />
      <svg width="360" height="360" viewBox="0 0 360 360" style={{
        position: 'absolute',
        top: '50%', left: '50%', transform: 'translate(-50%, -52%)',
        opacity: 0.5,
      }}>
        <circle cx="180" cy="180" r="160" fill="none" stroke={THEME.holoSoft} strokeWidth="1" strokeDasharray="2 6" />
        <circle cx="180" cy="180" r="140" fill="none" stroke={THEME.holoDim} strokeWidth="1" />
        <g style={{ animation: 'dcRotate 60s linear infinite', transformOrigin: '180px 180px' }}>
          <circle cx="180" cy="180" r="170" fill="none" stroke={THEME.holoEdge} strokeWidth="0.7" strokeDasharray="1 24" />
        </g>
      </svg>
      <div style={{
        position: 'relative',
        width: 200, height: 320,
        display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
        border: `1px dashed ${THEME.holoSoft}`,
        background: 'rgba(15,35,65,0.15)',
      }}>
        <CornerLs size={14} color={THEME.holoEdge} thickness={2} />
        <Icon.character width={64} height={64} style={{ color: THEME.holoSoft, opacity: 0.6 }} />
        <div style={{
          marginTop: 18,
          fontFamily: 'Rajdhani, sans-serif', fontSize: 12, fontWeight: 600,
          letterSpacing: 2, color: THEME.holoEdge,
          textTransform: 'uppercase', textAlign: 'center',
        }}>{merc.name} MODEL</div>
        <div style={{
          marginTop: 4,
          fontFamily: 'JetBrains Mono, monospace', fontSize: 9,
          color: THEME.textMute, textAlign: 'center',
        }}>ViewportFrame target</div>
      </div>

      {/* Handling button — overlapping lower edge of the model slot */}
      <button
        className="menu-btn"
        onClick={merc.hired ? onHandling : undefined}
        disabled={!merc.hired}
        style={{
          position: 'absolute',
          left: '50%',
          top: 'calc(50% + 132px)',
          transform: 'translateX(-50%)',
          padding: '10px 28px',
          border: `1px solid ${merc.hired ? THEME.holoEdge : THEME.holoDim}`,
          background: merc.hired
            ? `linear-gradient(180deg, rgba(40,90,150,0.85) 0%, rgba(20,50,90,0.85) 100%)`
            : 'rgba(10,24,44,0.72)',
          color: merc.hired ? THEME.text : THEME.textMute,
          fontFamily: 'Rajdhani, sans-serif', fontSize: 14, fontWeight: 700,
          letterSpacing: 4, textTransform: 'uppercase',
          display: 'flex', alignItems: 'center', gap: 10,
          cursor: merc.hired ? 'pointer' : 'not-allowed',
          boxShadow: merc.hired
            ? `0 0 24px -4px ${THEME.holo}, inset 0 0 12px -4px ${THEME.holoEdge}`
            : 'none',
          backdropFilter: 'blur(6px)',
          zIndex: 6,
        }}
      >
        <CornerLs size={8} color={merc.hired ? THEME.holoEdge : THEME.holoDim} thickness={1.5} />
        <Icon.diamond width={14} height={14} />
        <span>Handling</span>
        <Icon.chevR width={14} height={14} />
      </button>
    </div>
  );
}

function MercenaryPage({ onBack, onManage }) {
  const [selectedId, setSelectedId] = React.useState('pirate');
  const merc = MERCS.find(m => m.id === selectedId) || MERCS[0];

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
          MERCENARIES
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

      {/* LEFT: merc list */}
      <div style={{
        position: 'absolute',
        left: 24, top: 70, bottom: 24, width: 300,
        zIndex: 3,
      }}>
        <MercList selectedId={selectedId} onSelect={setSelectedId} />
      </div>

      {/* RIGHT: characteristics + manage */}
      <div style={{
        position: 'absolute',
        right: 24, top: 70, bottom: 24, width: 320,
        zIndex: 3,
      }}>
        <MercCharacteristics merc={merc} onManage={() => onManage && onManage(merc.id)} />
      </div>

      {/* CENTER: meta bar + character */}
      <div style={{
        position: 'absolute',
        left: 344, right: 364, top: 70, bottom: 24,
        display: 'flex', flexDirection: 'column', gap: 14,
        zIndex: 2,
      }}>
        <CharMetaBar merc={merc} />
        <div style={{ flex: 1, position: 'relative' }}>
          <MercCharacterSlot merc={merc} onHandling={() => onManage && onManage(merc.id)} />
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { MercenaryPage });
