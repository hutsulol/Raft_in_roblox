// MainMenu.jsx — top-level phone menu.
// Layout: level + stats (left) | Roblox character slot (center) | tasks + loadout (right)
// XP bar at the bottom of the center. Particles + sea-mist bg.

function TopBar({ onMenu }) {
  return (
    <div style={{
      position: 'absolute', top: 16, left: 16, right: 16,
      display: 'flex', alignItems: 'center', gap: 10,
      zIndex: 5,
    }}>
      {/* Roblox logo slot */}
      <div style={{
        width: 36, height: 36,
        background: 'rgba(10,24,44,0.72)',
        border: `1px solid ${THEME.holoSoft}`,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        position: 'relative',
      }}>
        <CornerLs size={6} color={THEME.holoEdge} />
        <div style={{
          width: 16, height: 16, background: THEME.holoSoft,
          transform: 'rotate(45deg)',
        }} />
      </div>
      <button className="menu-btn" style={buttonBase(36)}>
        <Icon.menu width={18} height={18} />
      </button>
      <button className="menu-btn" style={buttonBase(36)}>
        <Icon.chat width={18} height={18} />
      </button>
      <div style={{ flex: 1 }} />
      <div style={{
        fontFamily: 'Rajdhani, sans-serif', fontSize: 16, letterSpacing: 4,
        color: THEME.textDim, fontWeight: 500,
      }}>
        DAY&nbsp;&nbsp;01
      </div>
      <div style={{ flex: 1 }} />
      <div style={{ width: 36 * 3 + 20, opacity: 0 }} />
    </div>
  );
}

function buttonBase(size = 36) {
  return {
    width: size, height: size, border: `1px solid ${THEME.holoSoft}`,
    background: 'rgba(10,24,44,0.72)',
    color: THEME.text,
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    padding: 0,
  };
}

// ─── Left column ──────────────────────────────────────────────────────
function LevelCard({ name = 'hutsul', level = 3, points = 20 }) {
  return (
    <HoloFrame style={{ padding: 12, display: 'flex', gap: 12, alignItems: 'center' }}>
      <div style={{
        width: 54, height: 54, flexShrink: 0,
        border: `1px solid ${THEME.holoEdge}`,
        background: `linear-gradient(135deg, ${THEME.holoDeep} 0%, transparent 80%)`,
        display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
        position: 'relative',
      }}>
        <CornerLs size={5} color={THEME.holoEdge} />
        <div style={{
          fontSize: 9, letterSpacing: 2, color: THEME.holoEdge,
          fontFamily: 'Rajdhani, sans-serif', fontWeight: 600,
        }}>LVL</div>
        <div style={{
          fontFamily: 'Rajdhani, sans-serif', fontSize: 26, fontWeight: 700,
          lineHeight: 1, color: THEME.text,
        }}>{level}</div>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          fontFamily: 'Rajdhani, sans-serif', fontSize: 22, fontWeight: 700,
          color: THEME.text, letterSpacing: 0.5,
        }}>{name}</div>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 5, marginTop: 3,
          fontSize: 12, color: THEME.textDim,
        }}>
          <Icon.spark width={11} height={11} style={{ color: THEME.gold }} />
          <span>Upgrade points:</span>
          <span style={{ color: THEME.gold, fontWeight: 600, fontFamily: 'Rajdhani, sans-serif' }}>{points}</span>
        </div>
      </div>
    </HoloFrame>
  );
}

function StatRow({ icon: IconComp, label, level, fill, canUpgrade }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
      <div style={{
        width: 22, height: 22, flexShrink: 0,
        color: THEME.holoEdge,
      }}>
        <IconComp width={22} height={22} />
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          display: 'flex', justifyContent: 'space-between', alignItems: 'baseline',
          fontSize: 11, color: THEME.textDim, marginBottom: 4,
          fontFamily: 'Inter, sans-serif', letterSpacing: 0.5, textTransform: 'uppercase',
        }}>
          <span>{label}</span>
          <span style={{
            fontFamily: 'Rajdhani, sans-serif', color: THEME.text, fontSize: 12, fontWeight: 600,
          }}>LV {level}</span>
        </div>
        <HoloBar fill={fill} height={6} segments={10} />
      </div>
      <button className="menu-btn" style={{
        width: 22, height: 22, flexShrink: 0,
        border: `1px solid ${canUpgrade ? THEME.gold : THEME.holoDim}`,
        background: canUpgrade ? 'rgba(180,120,40,0.18)' : 'rgba(10,24,44,0.72)',
        color: canUpgrade ? THEME.gold : THEME.textMute,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        padding: 0, opacity: canUpgrade ? 1 : 0.5,
      }}>
        <Icon.plus width={12} height={12} />
      </button>
    </div>
  );
}

function PlayerStatsCard() {
  return (
    <HoloFrame style={{ padding: 14 }}>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 8, marginBottom: 12,
        paddingBottom: 10, borderBottom: `1px solid ${THEME.holoDim}`,
      }}>
        <Icon.diamond width={13} height={13} style={{ color: THEME.holoEdge }} />
        <div style={{
          fontFamily: 'Rajdhani, sans-serif', fontSize: 15, fontWeight: 700,
          color: THEME.text, letterSpacing: 2, textTransform: 'uppercase',
        }}>Player Stats</div>
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
        <StatRow icon={Icon.strength} label="Strength" level={2} fill={0.2} canUpgrade />
        <StatRow icon={Icon.mana} label="Mana" level={1} fill={0.1} canUpgrade />
        <StatRow icon={Icon.mutation} label="Mutation" level={0} fill={0} />
      </div>
    </HoloFrame>
  );
}

// ─── Right column ─────────────────────────────────────────────────────
function TaskRow({ icon: IconComp, text, progress, total, done }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
      <div style={{
        width: 18, height: 18, flexShrink: 0,
        border: `1px solid ${done ? THEME.holoEdge : THEME.holoDim}`,
        background: done ? 'rgba(120,200,255,0.2)' : 'transparent',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        color: THEME.holoEdge,
      }}>
        {done && <Icon.check width={12} height={12} />}
      </div>
      <IconComp width={16} height={16} style={{ color: THEME.textDim, flexShrink: 0 }} />
      <div style={{
        flex: 1, fontSize: 13, color: done ? THEME.textMute : THEME.text,
        textDecoration: done ? 'line-through' : 'none',
      }}>
        {text}
      </div>
      <div style={{
        fontFamily: 'Rajdhani, sans-serif', fontSize: 13, fontWeight: 600,
        color: done ? THEME.textMute : THEME.holoEdge,
      }}>
        {progress}/{total}
      </div>
    </div>
  );
}

function TasksCard() {
  return (
    <HoloFrame style={{ padding: 14 }}>
      <div style={{
        display: 'flex', justifyContent: 'space-between', alignItems: 'center',
        marginBottom: 12, paddingBottom: 10, borderBottom: `1px solid ${THEME.holoDim}`,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <Icon.scroll width={13} height={13} style={{ color: THEME.holoEdge }} />
          <div style={{
            fontFamily: 'Rajdhani, sans-serif', fontSize: 15, fontWeight: 700,
            color: THEME.text, letterSpacing: 2, textTransform: 'uppercase',
          }}>Daily Tasks</div>
        </div>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 4,
          fontSize: 11, color: THEME.textDim,
        }}>
          <Icon.clock width={11} height={11} />
          <span style={{ fontFamily: 'Rajdhani, sans-serif', fontWeight: 500 }}>18:12:17</span>
        </div>
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 10, marginBottom: 14 }}>
        <TaskRow icon={Icon.iron}  text="Smelt iron"    progress={0} total={2} />
        <TaskRow icon={Icon.stone} text="Collect stones" progress={0} total={3} />
        <TaskRow icon={Icon.log}   text="Collect logs"   progress={0} total={5} />
      </div>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 8, marginBottom: 10,
        fontSize: 12, color: THEME.textDim,
      }}>
        <span style={{
          fontFamily: 'Rajdhani, sans-serif', fontWeight: 600, letterSpacing: 1.5,
          textTransform: 'uppercase', color: THEME.text, fontSize: 11,
        }}>Reward</span>
        <div style={{ display: 'flex', alignItems: 'center', gap: 4, color: THEME.holoEdge }}>
          <Icon.xp width={13} height={13} /><span style={{ fontFamily: 'Rajdhani, sans-serif', fontWeight: 600 }}>+50 XP</span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 4, color: THEME.gold }}>
          <Icon.iron width={13} height={13} /><span style={{ fontFamily: 'Rajdhani, sans-serif', fontWeight: 600 }}>+2 Iron</span>
        </div>
      </div>
      <button className="menu-btn" style={{
        width: '100%', padding: '9px 0',
        border: `1px solid ${THEME.holoSoft}`,
        background: 'rgba(22,62,110,0.40)',
        color: THEME.text,
        fontFamily: 'Rajdhani, sans-serif', fontSize: 14, fontWeight: 600,
        letterSpacing: 2, textTransform: 'uppercase',
      }}>
        Claim Reward
      </button>
    </HoloFrame>
  );
}

function LoadoutCard({ onOpenMerc, onOpenArsenal }) {
  return (
    <HoloFrame style={{ padding: 14 }}>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 8, marginBottom: 12,
        paddingBottom: 10, borderBottom: `1px solid ${THEME.holoDim}`,
      }}>
        <Icon.crown width={13} height={13} style={{ color: THEME.holoEdge }} />
        <div style={{
          fontFamily: 'Rajdhani, sans-serif', fontSize: 15, fontWeight: 700,
          color: THEME.text, letterSpacing: 2, textTransform: 'uppercase',
        }}>Loadout</div>
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        <button className="menu-btn" onClick={onOpenArsenal} style={loadoutBtnStyle}>
          <Icon.sword width={16} height={16} style={{ color: THEME.holoEdge }} />
          <span>Arsenal</span>
          <Icon.chevR width={13} height={13} style={{ color: THEME.textDim, marginLeft: 'auto' }} />
        </button>
        <button className="menu-btn" onClick={onOpenMerc} style={loadoutBtnStyle}>
          <Icon.users width={16} height={16} style={{ color: THEME.holoEdge }} />
          <span>Mercenaries</span>
          <Icon.chevR width={13} height={13} style={{ color: THEME.textDim, marginLeft: 'auto' }} />
        </button>
      </div>
    </HoloFrame>
  );
}
const loadoutBtnStyle = {
  display: 'flex', alignItems: 'center', gap: 10,
  padding: '10px 12px',
  border: `1px solid ${THEME.holoDim}`,
  background: 'rgba(10,24,44,0.5)',
  color: THEME.text,
  fontFamily: 'Rajdhani, sans-serif', fontSize: 14, fontWeight: 600,
  letterSpacing: 1.5, textTransform: 'uppercase',
};

// ─── Center: Roblox character slot + XP bar ───────────────────────────
function CharacterSlot({ label = 'ROBLOX CHARACTER', sublabel = 'ViewportFrame target' }) {
  return (
    <div style={{
      position: 'relative',
      width: '100%', height: '100%',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      pointerEvents: 'none',
    }}>
      {/* Ground light disc */}
      <div style={{
        position: 'absolute', bottom: '12%', left: '50%',
        transform: 'translateX(-50%)',
        width: 240, height: 40,
        background: `radial-gradient(ellipse, ${THEME.holo} 0%, transparent 70%)`,
        opacity: 0.25, filter: 'blur(6px)',
      }} />
      {/* Rim circle behind character */}
      <svg width="320" height="320" viewBox="0 0 320 320" style={{
        position: 'absolute',
        top: '50%', left: '50%', transform: 'translate(-50%, -55%)',
        opacity: 0.4,
      }}>
        <circle cx="160" cy="160" r="140" fill="none" stroke={THEME.holoSoft} strokeWidth="1" strokeDasharray="2 6" />
        <circle cx="160" cy="160" r="120" fill="none" stroke={THEME.holoDim} strokeWidth="1" />
        <g style={{ animation: 'dcRotate 60s linear infinite', transformOrigin: '160px 160px' }}>
          <circle cx="160" cy="160" r="150" fill="none" stroke={THEME.holoSoft} strokeWidth="0.5" strokeDasharray="1 18" />
        </g>
      </svg>
      {/* Placeholder silhouette */}
      <div style={{
        position: 'relative',
        width: 180, height: 280,
        display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
        border: `1px dashed ${THEME.holoSoft}`,
        background: 'rgba(15,35,65,0.15)',
      }}>
        <CornerLs size={12} color={THEME.holoEdge} thickness={2} />
        <Icon.character width={56} height={56} style={{ color: THEME.holoSoft, opacity: 0.6 }} />
        <div style={{
          marginTop: 16,
          fontFamily: 'Rajdhani, sans-serif', fontSize: 11, fontWeight: 600,
          letterSpacing: 2, color: THEME.holoEdge,
          textTransform: 'uppercase', textAlign: 'center',
        }}>{label}</div>
        <div style={{
          marginTop: 4,
          fontFamily: 'JetBrains Mono, monospace', fontSize: 9,
          color: THEME.textMute, textAlign: 'center',
        }}>{sublabel}</div>
      </div>
    </div>
  );
}

function XPBar({ xp = 0, xpMax = 50, level = 3 }) {
  return (
    <HoloFrame style={{
      padding: '8px 14px',
      display: 'flex', alignItems: 'center', gap: 12,
    }}>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 6,
        color: THEME.holoEdge,
      }}>
        <Icon.xp width={16} height={16} />
        <span style={{
          fontFamily: 'Rajdhani, sans-serif', fontSize: 15, fontWeight: 700, letterSpacing: 1,
        }}>XP</span>
      </div>
      <div style={{
        fontFamily: 'Rajdhani, sans-serif', fontSize: 13, color: THEME.textDim,
        fontWeight: 500, minWidth: 48,
      }}>
        {xp} / {xpMax}
      </div>
      <div style={{ flex: 1 }}>
        <HoloBar fill={xp / xpMax} height={10} segments={10} />
      </div>
      <div style={{
        fontFamily: 'Rajdhani, sans-serif', fontSize: 13, fontWeight: 700, color: THEME.text,
        letterSpacing: 1,
      }}>
        Lv <span style={{ color: THEME.holoEdge }}>{level}</span>
      </div>
    </HoloFrame>
  );
}

// ─── Top layout ───────────────────────────────────────────────────────
function MainMenu({ onOpenMerc, onOpenArsenal }) {
  const [levelUpOpen, setLevelUpOpen] = React.useState(false);

  return (
    <div style={menuRoot}>
      <TopBar />

      {/* LEFT column */}
      <div style={{
        position: 'absolute',
        left: 24, top: 70, width: 280,
        display: 'flex', flexDirection: 'column', gap: 14,
        zIndex: 3,
      }}>
        <LevelCard />
        <PlayerStatsCard />
      </div>

      {/* RIGHT column */}
      <div style={{
        position: 'absolute',
        right: 24, top: 70, width: 280,
        display: 'flex', flexDirection: 'column', gap: 14,
        zIndex: 3,
      }}>
        <TasksCard />
        <LoadoutCard onOpenMerc={onOpenMerc} onOpenArsenal={onOpenArsenal} />
      </div>

      {/* CENTER character */}
      <div style={{
        position: 'absolute',
        left: 320, right: 320, top: 40, bottom: 80,
        zIndex: 2,
      }}>
        <CharacterSlot />
      </div>

      {/* XP BAR */}
      <div style={{
        position: 'absolute',
        left: '50%', bottom: 24, transform: 'translateX(-50%)',
        width: 460, zIndex: 4,
      }}>
        <XPBar />
      </div>

      {/* Dev trigger — simulate level up */}
      <button
        className="menu-btn"
        onClick={() => setLevelUpOpen(true)}
        style={{
          position: 'absolute', bottom: 64, left: '50%',
          transform: 'translateX(-50%)',
          padding: '6px 14px',
          border: `1px dashed ${THEME.success}`,
          background: 'rgba(18,40,28,0.55)',
          color: THEME.success,
          fontFamily: 'Rajdhani, sans-serif', fontSize: 11, fontWeight: 700,
          letterSpacing: 2, textTransform: 'uppercase',
          zIndex: 4,
        }}
      >
        +25 XP (DEV)
      </button>

      <LevelUpModal
        open={levelUpOpen}
        fromLevel={4}
        toLevel={5}
        instantRewards={[
          { icon: Icon.strength, label: '+1 Upgrade Point' },
          { icon: Icon.log, label: '+5 Logs', tint: THEME.gold },
        ]}
        unlocks={[
          { icon: Icon.flask, label: 'Cup' },
          { icon: Icon.vial,  label: 'Water Purifier' },
        ]}
        onContinue={() => setLevelUpOpen(false)}
      />
    </div>
  );
}
const menuRoot = {
  position: 'absolute', inset: 0,
  fontFamily: 'Inter, sans-serif',
  color: THEME.text,
};

Object.assign(window, { MainMenu });
