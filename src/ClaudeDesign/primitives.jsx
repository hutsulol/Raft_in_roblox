// primitives.jsx — shared visual language for all 3 menu screens.
// Minimal-fantasy frame with corner L-accents, holo-blue palette,
// decorative SVG icons, particle background.

const THEME = {
  // Морская дымка — deep ocean night with cool haze
  bgA: '#081322',
  bgB: '#0d1f35',
  bgC: '#153352',
  // holo blue accents
  holo:       'oklch(0.82 0.12 220)',
  holoSoft:   'oklch(0.70 0.10 220)',
  holoDim:    'oklch(0.55 0.08 220)',
  holoDeep:   'oklch(0.30 0.06 230)',
  holoEdge:   'oklch(0.90 0.14 215)',
  // panel fills
  panel:      'rgba(10, 24, 44, 0.72)',
  panelSolid: 'rgba(10, 24, 44, 0.92)',
  panelHi:    'rgba(22, 48, 82, 0.60)',
  // text
  text:     'oklch(0.96 0.02 220)',
  textDim:  'oklch(0.72 0.04 220)',
  textMute: 'oklch(0.55 0.03 220)',
  // semantic
  gold:     'oklch(0.85 0.14 85)',
  danger:   'oklch(0.68 0.19 25)',
  success:  'oklch(0.72 0.15 150)',
};

// ──────────────────────────────────────────────────────────────
// HoloFrame — panel with tonal fill + thin border + corner L's.
// variant: 'default' | 'solid' | 'subtle' | 'active'
// ──────────────────────────────────────────────────────────────
function HoloFrame({ children, variant = 'default', corners = true, glow = false, style = {}, ...rest }) {
  const fill = variant === 'solid' ? THEME.panelSolid
             : variant === 'subtle' ? 'rgba(10,24,44,0.45)'
             : variant === 'active' ? 'rgba(22,62,110,0.70)'
             : THEME.panel;
  const borderCol = variant === 'active' ? THEME.holoEdge : THEME.holoDim;
  return (
    <div
      {...rest}
      style={{
        position: 'relative',
        background: fill,
        border: `1px solid ${borderCol}`,
        backdropFilter: 'blur(6px)',
        WebkitBackdropFilter: 'blur(6px)',
        boxShadow: glow
          ? `0 0 0 1px ${THEME.holoSoft}, 0 0 24px -4px ${THEME.holo}, inset 0 0 20px rgba(120,200,255,0.04)`
          : `inset 0 0 20px rgba(120,200,255,0.03)`,
        ...style,
      }}
    >
      {corners && <CornerLs color={variant === 'active' ? THEME.holoEdge : THEME.holoSoft} />}
      {children}
    </div>
  );
}

// Four angular L-shaped corner accents — minimal fantasy touch without ornament.
function CornerLs({ size = 10, color = THEME.holoSoft, thickness = 1.5 }) {
  const s = { position: 'absolute', width: size, height: size, pointerEvents: 'none' };
  const hor = `${thickness}px solid ${color}`;
  const ver = `${thickness}px solid ${color}`;
  return (
    <>
      <div style={{ ...s, top: -1, left: -1, borderTop: hor, borderLeft: ver }} />
      <div style={{ ...s, top: -1, right: -1, borderTop: hor, borderRight: ver }} />
      <div style={{ ...s, bottom: -1, left: -1, borderBottom: hor, borderLeft: ver }} />
      <div style={{ ...s, bottom: -1, right: -1, borderBottom: hor, borderRight: ver }} />
    </>
  );
}

// ──────────────────────────────────────────────────────────────
// Icons — original decorative SVGs (no brand marks).
// All stroke-based so they inherit color via currentColor.
// ──────────────────────────────────────────────────────────────
const Icon = {
  strength: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" {...p}>
      <path d="M12 2 L14 7 L19 8 L15.5 11.5 L16.5 17 L12 14.5 L7.5 17 L8.5 11.5 L5 8 L10 7 Z" />
      <path d="M9 20 L15 20" />
    </svg>
  ),
  mana: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" {...p}>
      <path d="M12 3 C12 3 5 10 5 15 a7 7 0 0 0 14 0 C19 10 12 3 12 3 Z" />
      <path d="M9 14 a3 3 0 0 0 3 3" opacity="0.5" />
    </svg>
  ),
  mutation: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" {...p}>
      <path d="M7 4 C7 4 17 8 17 12 C17 16 7 20 7 20" />
      <path d="M17 4 C17 4 7 8 7 12 C7 16 17 20 17 20" />
      <circle cx="7" cy="8" r="0.8" fill="currentColor" />
      <circle cx="17" cy="16" r="0.8" fill="currentColor" />
    </svg>
  ),
  sword: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" {...p}>
      <path d="M14.5 3 L21 3 L21 9.5 L10 20.5 L7 20.5 L3.5 17 L3.5 14 Z" />
      <path d="M6 18 L2 22" />
      <path d="M14 10 L10 14" opacity="0.4" />
    </svg>
  ),
  shield: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" {...p}>
      <path d="M12 3 L20 6 V12 C20 16 16 20 12 21 C8 20 4 16 4 12 V6 Z" />
      <path d="M12 8 V14" opacity="0.5" />
      <path d="M9 11 H15" opacity="0.5" />
    </svg>
  ),
  crown: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" {...p}>
      <path d="M3 8 L6 14 L9 10 L12 15 L15 10 L18 14 L21 8 L19 18 L5 18 Z" />
    </svg>
  ),
  users: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" {...p}>
      <circle cx="9" cy="8" r="3.5" />
      <path d="M3 19 C3 15.5 6 13.5 9 13.5 C12 13.5 15 15.5 15 19" />
      <path d="M15 8.5 a3 3 0 0 1 0 5" opacity="0.6" />
      <path d="M17 19 C17 17 19 15.5 21 15.5" opacity="0.6" />
    </svg>
  ),
  scroll: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" {...p}>
      <path d="M6 4 H17 A2 2 0 0 1 19 6 V18 A2 2 0 0 0 21 20 H8 A2 2 0 0 1 6 18 Z" />
      <path d="M3 6 A2 2 0 0 1 5 4 V18" opacity="0.6" />
      <path d="M9 9 H15 M9 12 H15 M9 15 H13" opacity="0.7" />
    </svg>
  ),
  star: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="currentColor" {...p}>
      <path d="M12 2 L14.5 8.5 L21.5 9 L16 13.5 L17.5 20.5 L12 16.5 L6.5 20.5 L8 13.5 L2.5 9 L9.5 8.5 Z" />
    </svg>
  ),
  starEmpty: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" {...p}>
      <path d="M12 2 L14.5 8.5 L21.5 9 L16 13.5 L17.5 20.5 L12 16.5 L6.5 20.5 L8 13.5 L2.5 9 L9.5 8.5 Z" />
    </svg>
  ),
  diamond: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" {...p}>
      <path d="M12 3 L21 12 L12 21 L3 12 Z" />
      <path d="M7.5 12 L12 7.5 L16.5 12 L12 16.5 Z" opacity="0.5" />
    </svg>
  ),
  check: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" {...p}>
      <path d="M5 12.5 L10 17.5 L19 7" />
    </svg>
  ),
  plus: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" {...p}>
      <path d="M12 5 V19 M5 12 H19" />
    </svg>
  ),
  lock: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" {...p}>
      <rect x="5" y="11" width="14" height="10" rx="1.5" />
      <path d="M8 11 V8 a4 4 0 0 1 8 0 V11" />
    </svg>
  ),
  hand: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" {...p}>
      <path d="M9 11 V5.5 a1.5 1.5 0 0 1 3 0 V11 M12 11 V4.5 a1.5 1.5 0 0 1 3 0 V11 M15 11 V6 a1.5 1.5 0 0 1 3 0 V14 C18 18 15 21 11 21 C8 21 6 19 6 16 L6 12 a1.5 1.5 0 0 1 3 0" />
    </svg>
  ),
  rod: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" {...p}>
      <path d="M4 20 L19 5" />
      <path d="M19 5 L20 4 M16 8 L18 6" />
      <path d="M4 20 C7 18 10 18 12 20" opacity="0.6" />
      <circle cx="13" cy="20" r="1" fill="currentColor" />
    </svg>
  ),
  bag: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" {...p}>
      <path d="M6 8 H18 L19 20 A1 1 0 0 1 18 21 H6 A1 1 0 0 1 5 20 Z" />
      <path d="M9 8 V6 a3 3 0 0 1 6 0 V8" />
      <path d="M9 12 H15" opacity="0.5" />
    </svg>
  ),
  back: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" {...p}>
      <path d="M15 5 L7 12 L15 19" />
    </svg>
  ),
  chevR: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" {...p}>
      <path d="M9 5 L17 12 L9 19" />
    </svg>
  ),
  iron: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" {...p}>
      <path d="M5 8 L12 4 L19 8 L19 16 L12 20 L5 16 Z" />
      <path d="M5 8 L12 12 L19 8 M12 12 V20" opacity="0.5" />
    </svg>
  ),
  stone: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" {...p}>
      <path d="M4 15 C4 11 7 7 12 7 C17 7 20 11 20 15 C20 18 17 20 12 20 C7 20 4 18 4 15 Z" />
      <path d="M8 13 L10 11 M13 12 L15 14" opacity="0.5" />
    </svg>
  ),
  log: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" {...p}>
      <ellipse cx="7" cy="12" rx="3" ry="7" />
      <path d="M7 5 L20 5 M7 19 L20 19 M10 12 L20 12" />
      <circle cx="7" cy="12" r="1.2" opacity="0.5" />
    </svg>
  ),
  xp: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" {...p}>
      <path d="M12 3 L15 9 L21 10 L16.5 14.5 L18 21 L12 17.5 L6 21 L7.5 14.5 L3 10 L9 9 Z" />
      <path d="M12 9 V15 M9 12 H15" opacity="0.6" />
    </svg>
  ),
  spark: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="currentColor" {...p}>
      <path d="M12 2 L13 10 L21 12 L13 14 L12 22 L11 14 L3 12 L11 10 Z" />
    </svg>
  ),
  gem: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" {...p}>
      <path d="M6 4 H18 L22 10 L12 22 L2 10 Z" />
      <path d="M2 10 H22 M6 4 L12 10 L18 4 M12 10 V22" opacity="0.5" />
    </svg>
  ),
  hp: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" {...p}>
      <path d="M12 21 C12 21 3 15 3 8.5 A4.5 4.5 0 0 1 12 6 A4.5 4.5 0 0 1 21 8.5 C21 15 12 21 12 21 Z" />
    </svg>
  ),
  damage: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" {...p}>
      <path d="M13 2 L4 14 H11 L10 22 L20 10 H13 Z" />
    </svg>
  ),
  menu: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" {...p}>
      <path d="M4 7 H20 M4 12 H20 M4 17 H20" />
    </svg>
  ),
  chat: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" {...p}>
      <path d="M4 5 H20 A1 1 0 0 1 21 6 V16 A1 1 0 0 1 20 17 H13 L9 21 V17 H4 A1 1 0 0 1 3 16 V6 A1 1 0 0 1 4 5 Z" />
    </svg>
  ),
  phone: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" {...p}>
      <rect x="6" y="2" width="12" height="20" rx="2" />
      <path d="M9 5 H15 M11 19 H13" opacity="0.5" />
    </svg>
  ),
  clock: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" {...p}>
      <circle cx="12" cy="12" r="9" />
      <path d="M12 7 V12 L15.5 14" />
    </svg>
  ),
  character: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" {...p}>
      <circle cx="12" cy="7" r="3.5" />
      <path d="M5 21 C5 17 8 14 12 14 C16 14 19 17 19 21" />
    </svg>
  ),
  flask: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" {...p}>
      <path d="M9 3 H15 M10 3 V10 L5 19 A1 1 0 0 0 6 20 H18 A1 1 0 0 0 19 19 L14 10 V3" />
      <path d="M7.5 15 H16.5" opacity="0.5" />
    </svg>
  ),
  about: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" {...p}>
      <circle cx="12" cy="12" r="9" />
      <path d="M12 8 V8.1 M12 11 V16" />
    </svg>
  ),
  close: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" {...p}>
      <path d="M6 6 L18 18 M18 6 L6 18" />
    </svg>
  ),
  dna: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" {...p}>
      <path d="M7 3 C7 3 17 8 17 12 C17 16 7 21 7 21" />
      <path d="M17 3 C17 3 7 8 7 12 C7 16 17 21 17 21" />
      <path d="M8 7 H16 M7.5 10 H16.5 M7.5 14 H16.5 M8 17 H16" opacity="0.5" />
    </svg>
  ),
  helix: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" {...p}>
      <path d="M5 3 Q12 7 5 12 Q12 17 5 21" />
      <path d="M19 3 Q12 7 19 12 Q12 17 19 21" />
    </svg>
  ),
  vial: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" {...p}>
      <path d="M10 2 V8 L6 14 V20 A2 2 0 0 0 8 22 H16 A2 2 0 0 0 18 20 V14 L14 8 V2" />
      <path d="M9 2 H15" />
      <path d="M7 16 H17" opacity="0.5" />
      <circle cx="10.5" cy="18" r="0.6" fill="currentColor" opacity="0.6" />
      <circle cx="13.5" cy="19.5" r="0.6" fill="currentColor" opacity="0.6" />
    </svg>
  ),
  mask: (p = {}) => (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" {...p}>
      <path d="M4 8 C4 5 7 3 12 3 C17 3 20 5 20 8 V13 C20 17 16 21 12 21 C8 21 4 17 4 13 Z" />
      <path d="M8 10 H10 M14 10 H16" />
      <path d="M10 14 Q12 16 14 14" opacity="0.6" />
    </svg>
  ),
};

// ──────────────────────────────────────────────────────────────
// Stars — filled/empty star row for rarity display.
// ──────────────────────────────────────────────────────────────
function StarRow({ filled = 1, total = 5, size = 12, color = THEME.gold }) {
  return (
    <div style={{ display: 'inline-flex', gap: 2, color }}>
      {Array.from({ length: total }).map((_, i) => (
        i < filled
          ? <Icon.star key={i} width={size} height={size} />
          : <Icon.starEmpty key={i} width={size} height={size} style={{ opacity: 0.35 }} />
      ))}
    </div>
  );
}

// ──────────────────────────────────────────────────────────────
// HoloBar — progress bar with holo glow. fill is 0-1.
// ──────────────────────────────────────────────────────────────
function HoloBar({ fill = 0, height = 8, color = THEME.holo, bg = 'rgba(8,20,38,0.8)', segments = 0 }) {
  const pct = Math.max(0, Math.min(1, fill)) * 100;
  return (
    <div style={{
      position: 'relative',
      height,
      background: bg,
      border: `1px solid ${THEME.holoDim}`,
      overflow: 'hidden',
    }}>
      <div style={{
        position: 'absolute', inset: 0, width: `${pct}%`,
        background: `linear-gradient(90deg, ${color}, ${THEME.holoEdge})`,
        boxShadow: `0 0 8px ${color}, inset 0 0 4px rgba(255,255,255,0.3)`,
      }} />
      {segments > 0 && (
        <div style={{ position: 'absolute', inset: 0, display: 'flex', pointerEvents: 'none' }}>
          {Array.from({ length: segments - 1 }).map((_, i) => (
            <div key={i} style={{ flex: 1, borderRight: `1px solid rgba(8,20,38,0.6)` }} />
          ))}
          <div style={{ flex: 1 }} />
        </div>
      )}
    </div>
  );
}

// ──────────────────────────────────────────────────────────────
// MenuBackground — layered sea-mist backdrop + particles.
// Claude Code will replace this with whatever matches in Roblox —
// here it's purely decorative HTML for the mockup.
// ──────────────────────────────────────────────────────────────
function MenuBackground({ particles = true, variant = 'mist' }) {
  // SVG noise/haze texture.
  const hazeUrl = "data:image/svg+xml;utf8," + encodeURIComponent(
    `<svg xmlns='http://www.w3.org/2000/svg' width='600' height='400'>
      <defs>
        <radialGradient id='g1' cx='30%' cy='35%' r='55%'>
          <stop offset='0%' stop-color='%23264a74' stop-opacity='0.9'/>
          <stop offset='100%' stop-color='%23264a74' stop-opacity='0'/>
        </radialGradient>
        <radialGradient id='g2' cx='75%' cy='70%' r='60%'>
          <stop offset='0%' stop-color='%231b3a5e' stop-opacity='0.7'/>
          <stop offset='100%' stop-color='%231b3a5e' stop-opacity='0'/>
        </radialGradient>
      </defs>
      <rect width='600' height='400' fill='url(%23g1)'/>
      <rect width='600' height='400' fill='url(%23g2)'/>
    </svg>`
  );

  return (
    <div style={{ position: 'absolute', inset: 0, overflow: 'hidden', pointerEvents: 'none' }}>
      {/* Base vertical gradient */}
      <div style={{
        position: 'absolute', inset: 0,
        background: `linear-gradient(180deg, ${THEME.bgA} 0%, ${THEME.bgB} 45%, ${THEME.bgC} 100%)`,
      }} />
      {/* Radial haze */}
      <div style={{
        position: 'absolute', inset: 0,
        backgroundImage: `url("${hazeUrl}")`,
        backgroundSize: 'cover',
        opacity: 0.85,
        mixBlendMode: 'screen',
      }} />
      {/* Horizon light band */}
      <div style={{
        position: 'absolute', left: 0, right: 0, top: '38%', height: '12%',
        background: `radial-gradient(ellipse at 50% 50%, oklch(0.65 0.08 225 / 0.35), transparent 70%)`,
      }} />
      {/* Subtle scan-line noise to feel digital */}
      <div style={{
        position: 'absolute', inset: 0, opacity: 0.06,
        backgroundImage: 'repeating-linear-gradient(0deg, rgba(255,255,255,0.4) 0, rgba(255,255,255,0.4) 1px, transparent 1px, transparent 3px)',
      }} />
      {/* Vignette */}
      <div style={{
        position: 'absolute', inset: 0,
        background: 'radial-gradient(ellipse at center, transparent 40%, rgba(0,0,0,0.55) 100%)',
      }} />
      {particles && <Particles />}
    </div>
  );
}

// Drifting light motes — rendered as absolute divs with CSS animation.
function Particles({ count = 26 }) {
  const parts = React.useMemo(() => Array.from({ length: count }).map((_, i) => ({
    left: Math.random() * 100,
    size: 1 + Math.random() * 2.5,
    delay: -Math.random() * 18,
    dur: 14 + Math.random() * 14,
    drift: (Math.random() - 0.5) * 40,
    opacity: 0.2 + Math.random() * 0.6,
  })), [count]);
  return (
    <div style={{ position: 'absolute', inset: 0 }}>
      {parts.map((p, i) => (
        <div key={i} style={{
          position: 'absolute',
          left: `${p.left}%`, bottom: -10,
          width: p.size, height: p.size,
          borderRadius: '50%',
          background: `oklch(0.88 0.10 215 / ${p.opacity})`,
          boxShadow: `0 0 ${p.size * 3}px oklch(0.88 0.10 215 / ${p.opacity})`,
          animation: `dcDrift ${p.dur}s linear ${p.delay}s infinite`,
          ['--drift']: `${p.drift}px`,
        }} />
      ))}
    </div>
  );
}

// Keyframes + base reset — injected once.
(function injectCss() {
  if (document.getElementById('menu-keyframes')) return;
  const s = document.createElement('style');
  s.id = 'menu-keyframes';
  s.textContent = `
    @keyframes dcDrift {
      0% { transform: translate(0, 0); opacity: 0; }
      10% { opacity: 1; }
      90% { opacity: 1; }
      100% { transform: translate(var(--drift, 0), -110vh); opacity: 0; }
    }
    @keyframes dcPulse {
      0%, 100% { opacity: 0.4; }
      50% { opacity: 1; }
    }
    @keyframes dcFadeIn {
      from { opacity: 0; transform: translateY(8px); }
      to { opacity: 1; transform: translateY(0); }
    }
    @keyframes dcScan {
      0% { transform: translateY(-100%); }
      100% { transform: translateY(100%); }
    }
    @keyframes dcRotate {
      to { transform: rotate(360deg); }
    }
    .menu-btn { transition: all .15s ease; cursor: pointer; }
    .menu-btn:hover { background: rgba(40,90,150,0.5) !important; border-color: var(--holo-edge, oklch(0.90 0.14 215)) !important; }
    .menu-btn:active { transform: translateY(1px); }
    .menu-nav { transition: all .12s ease; cursor: pointer; position: relative; }
    .menu-nav:hover { color: oklch(0.90 0.14 215) !important; padding-left: 6px; }
    .menu-nav.active { color: oklch(0.90 0.14 215) !important; }
    .menu-card { transition: all .15s ease; cursor: pointer; }
    .menu-card:hover { transform: translateY(-2px); box-shadow: 0 6px 20px -4px oklch(0.70 0.10 220 / 0.4); }
  `;
  document.head.appendChild(s);
})();

Object.assign(window, { THEME, HoloFrame, CornerLs, Icon, StarRow, HoloBar, MenuBackground, Particles });
