// LevelUpModal.jsx — dialog that slides in on level-up.
// Same holo-blue language as the rest of the menu: corner L's, thin
// border, scan-line interior, gold accent for the celebratory heading.

function LevelUpRewardTile({ icon: IconComp, label, tint = THEME.holoEdge, compact = false }) {
  return (
    <div style={{
      position: 'relative',
      display: 'flex', alignItems: 'center', gap: 10,
      padding: compact ? '8px 12px' : '10px 14px',
      background: 'rgba(10,24,44,0.55)',
      border: `1px solid ${THEME.holoDim}`,
      flex: 1, minWidth: 0,
    }}>
      <CornerLs size={5} color={THEME.holoSoft} />
      <div style={{
        width: compact ? 28 : 32, height: compact ? 28 : 32, flexShrink: 0,
        border: `1px solid ${tint}`,
        background: `linear-gradient(135deg, ${THEME.holoDeep} 0%, transparent 80%)`,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        color: tint,
      }}>
        <IconComp width={compact ? 16 : 18} height={compact ? 16 : 18} />
      </div>
      <div style={{
        fontFamily: 'Rajdhani, sans-serif', fontSize: 14, fontWeight: 600,
        color: THEME.text, letterSpacing: 0.5,
        whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
      }}>{label}</div>
    </div>
  );
}

function LevelUpUnlockCard({ icon: IconComp, label }) {
  return (
    <div style={{
      position: 'relative',
      flex: 1,
      padding: '16px 10px 12px',
      background: 'rgba(22,48,82,0.45)',
      border: `1px solid ${THEME.holoSoft}`,
      display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8,
      boxShadow: `inset 0 0 16px rgba(120,200,255,0.05)`,
    }}>
      <CornerLs size={7} color={THEME.holoEdge} />
      <div style={{
        width: 56, height: 56,
        border: `1px solid ${THEME.holoEdge}`,
        background: `radial-gradient(ellipse at 50% 30%, ${THEME.holoDeep} 0%, rgba(10,24,44,0.8) 80%)`,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        color: THEME.holoEdge,
        boxShadow: `0 0 18px -4px ${THEME.holo}`,
      }}>
        <IconComp width={32} height={32} />
      </div>
      <div style={{
        fontFamily: 'Rajdhani, sans-serif', fontSize: 14, fontWeight: 700,
        color: THEME.text, letterSpacing: 1,
        textAlign: 'center',
      }}>{label}</div>
    </div>
  );
}

function LevelUpModal({
  open,
  fromLevel = 4,
  toLevel = 5,
  instantRewards = [
    { icon: Icon.strength, label: '+1 Upgrade Point' },
    { icon: Icon.log, label: '+5 Logs', tint: THEME.gold },
  ],
  unlocks = [
    { icon: Icon.flask, label: 'Cup' },
    { icon: Icon.vial,  label: 'Water Purifier' },
  ],
  onContinue,
}) {
  if (!open) return null;

  return (
    <div
      style={{
        position: 'absolute', inset: 0,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        background: 'rgba(5,12,24,0.55)',
        backdropFilter: 'blur(3px)',
        WebkitBackdropFilter: 'blur(3px)',
        zIndex: 50,
        animation: 'dcFadeIn .22s ease both',
        fontFamily: 'Inter, sans-serif',
      }}
    >
      {/* Dialog */}
      <div style={{
        position: 'relative',
        width: 420,
        padding: '26px 26px 22px',
        background: `linear-gradient(180deg, rgba(12,28,52,0.94) 0%, rgba(8,20,38,0.94) 100%)`,
        border: `1px solid ${THEME.holoEdge}`,
        boxShadow: `0 0 0 1px ${THEME.holoSoft}, 0 0 50px -8px ${THEME.holo}, inset 0 0 30px rgba(120,200,255,0.06)`,
        animation: 'dcFadeIn .28s ease both',
      }}>
        <CornerLs size={14} color={THEME.holoEdge} thickness={2} />

        {/* Scan-line interior texture */}
        <div style={{
          position: 'absolute', inset: 1, pointerEvents: 'none', opacity: 0.06,
          backgroundImage: 'repeating-linear-gradient(0deg, rgba(255,255,255,0.4) 0, rgba(255,255,255,0.4) 1px, transparent 1px, transparent 3px)',
        }} />

        {/* Heading */}
        <div style={{
          fontFamily: 'Rajdhani, sans-serif', fontWeight: 700,
          fontSize: 22, letterSpacing: 2, textAlign: 'center',
          color: THEME.gold,
          textShadow: `0 0 18px ${THEME.gold}66`,
          textTransform: 'none',
        }}>
          Your level has increased!
        </div>

        {/* Level transition */}
        <div style={{
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 18,
          margin: '14px 0 22px',
        }}>
          <div style={{
            fontFamily: 'Rajdhani, sans-serif', fontSize: 42, fontWeight: 700,
            color: THEME.holoEdge,
            lineHeight: 1,
            textShadow: `0 0 20px ${THEME.holo}`,
          }}>{fromLevel}</div>
          <svg width="32" height="20" viewBox="0 0 32 20" fill="none" style={{ color: THEME.holoEdge }}>
            <path d="M2 10 H26 M20 4 L28 10 L20 16" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
          <div style={{
            fontFamily: 'Rajdhani, sans-serif', fontSize: 42, fontWeight: 700,
            color: THEME.holoEdge,
            lineHeight: 1,
            textShadow: `0 0 24px ${THEME.holo}`,
          }}>{toLevel}</div>
        </div>

        {/* Instant Rewards */}
        <div style={{
          display: 'flex', alignItems: 'center', gap: 8, marginBottom: 10,
        }}>
          <Icon.spark width={13} height={13} style={{ color: THEME.holoEdge }} />
          <div style={{
            fontFamily: 'Rajdhani, sans-serif', fontSize: 13, fontWeight: 700,
            color: THEME.text, letterSpacing: 2, textTransform: 'uppercase',
          }}>Instant Rewards</div>
          <div style={{ flex: 1, height: 1, background: THEME.holoDim }} />
        </div>
        <div style={{ display: 'flex', gap: 10, marginBottom: 20 }}>
          {instantRewards.map((r, i) => (
            <LevelUpRewardTile key={i} icon={r.icon} label={r.label} tint={r.tint || THEME.holoEdge} compact />
          ))}
        </div>

        {/* Unlocked */}
        <div style={{
          display: 'flex', alignItems: 'center', gap: 8, marginBottom: 10,
        }}>
          <Icon.diamond width={13} height={13} style={{ color: THEME.holoEdge }} />
          <div style={{
            fontFamily: 'Rajdhani, sans-serif', fontSize: 13, fontWeight: 700,
            color: THEME.text, letterSpacing: 2, textTransform: 'uppercase',
          }}>Unlocked</div>
          <div style={{ flex: 1, height: 1, background: THEME.holoDim }} />
        </div>
        <div style={{ display: 'flex', gap: 10, marginBottom: 22 }}>
          {unlocks.map((u, i) => (
            <LevelUpUnlockCard key={i} icon={u.icon} label={u.label} />
          ))}
        </div>

        {/* Continue */}
        <button
          className="menu-btn"
          onClick={onContinue}
          style={{
            width: '100%',
            padding: '12px 0',
            border: `1px solid ${THEME.holoEdge}`,
            background: `linear-gradient(180deg, rgba(40,90,150,0.70) 0%, rgba(20,50,90,0.70) 100%)`,
            color: THEME.text,
            fontFamily: 'Rajdhani, sans-serif', fontSize: 15, fontWeight: 700,
            letterSpacing: 4, textTransform: 'uppercase',
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 10,
            cursor: 'pointer',
            position: 'relative',
            boxShadow: `0 0 20px -4px ${THEME.holo}, inset 0 0 14px -4px ${THEME.holoEdge}`,
          }}
        >
          <CornerLs size={8} color={THEME.holoEdge} thickness={1.5} />
          <Icon.check width={14} height={14} />
          <span>Continue</span>
        </button>
      </div>
    </div>
  );
}

Object.assign(window, { LevelUpModal, LevelUpRewardTile, LevelUpUnlockCard });
