use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct RgbaColor {
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: f32,
    pub raw: &'static str,
}

impl RgbaColor {
    pub const fn hex(raw: &'static str, r: u8, g: u8, b: u8) -> Self {
        Self {
            r,
            g,
            b,
            a: 1.0,
            raw,
        }
    }

    pub const fn rgba(raw: &'static str, r: u8, g: u8, b: u8, a: f32) -> Self {
        Self { r, g, b, a, raw }
    }

    pub const fn alpha_u8(&self) -> u8 {
        let clamped = if self.a < 0.0 {
            0.0
        } else if self.a > 1.0 {
            1.0
        } else {
            self.a
        };
        let scaled = clamped * 255.0 + 0.5;
        if scaled >= 255.0 {
            255
        } else if scaled <= 0.0 {
            0
        } else {
            scaled as u8
        }
    }

    pub fn to_rgba_u8(&self) -> (u8, u8, u8, u8) {
        let a = (self.a.clamp(0.0, 1.0) * 255.0).round() as u8;
        (self.r, self.g, self.b, a)
    }

    pub fn to_argb_u32(&self) -> u32 {
        let (_, _, _, a) = self.to_rgba_u8();
        ((a as u32) << 24) | ((self.r as u32) << 16) | ((self.g as u32) << 8) | (self.b as u32)
    }

    pub fn as_str(&self) -> &'static str {
        self.raw
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ShadowLayer {
    pub offset_x: f32,
    pub offset_y: f32,
    pub blur: f32,
    pub spread: f32,
    pub color: RgbaColor,
}

impl ShadowLayer {
    pub const fn new(
        offset_x: f32,
        offset_y: f32,
        blur: f32,
        spread: f32,
        color: RgbaColor,
    ) -> Self {
        Self {
            offset_x,
            offset_y,
            blur,
            spread,
            color,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ShadowSpec {
    pub layers: &'static [ShadowLayer],
    pub raw: &'static str,
}

impl ShadowSpec {
    pub const fn primary(&self) -> ShadowLayer {
        self.layers[0]
    }

    pub const fn secondary(&self) -> Option<ShadowLayer> {
        if self.layers.len() > 1 {
            Some(self.layers[1])
        } else {
            None
        }
    }

    pub fn as_str(&self) -> &'static str {
        self.raw
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct GlowSpec {
    pub rx_px: f32,
    pub ry_px: f32,
    pub cx_pct: f32,
    pub cy_pct: f32,
    pub color: RgbaColor,
    pub stop_pct: f32,
    pub raw: &'static str,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum ThemeId {
    #[serde(rename = "dark")]
    Dark,
    #[serde(rename = "oled-obsidian")]
    OledObsidian,
    #[serde(rename = "emerald-ops")]
    EmeraldOps,
    #[serde(rename = "graphite-amber")]
    GraphiteAmber,
    #[serde(rename = "midnight-violet")]
    MidnightViolet,
    #[serde(rename = "light")]
    Light,
    #[serde(rename = "daylight-warm")]
    DaylightWarm,
    #[serde(rename = "frost-slate")]
    FrostSlate,
}

impl ThemeId {
    pub const ALL: [ThemeId; 8] = [
        Self::Dark,
        Self::OledObsidian,
        Self::EmeraldOps,
        Self::GraphiteAmber,
        Self::MidnightViolet,
        Self::Light,
        Self::DaylightWarm,
        Self::FrostSlate,
    ];

    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Dark => "dark",
            Self::OledObsidian => "oled-obsidian",
            Self::EmeraldOps => "emerald-ops",
            Self::GraphiteAmber => "graphite-amber",
            Self::MidnightViolet => "midnight-violet",
            Self::Light => "light",
            Self::DaylightWarm => "daylight-warm",
            Self::FrostSlate => "frost-slate",
        }
    }

    pub const fn is_dark(self) -> bool {
        matches!(
            self,
            Self::Dark
                | Self::OledObsidian
                | Self::EmeraldOps
                | Self::GraphiteAmber
                | Self::MidnightViolet
        )
    }

    pub fn parse(raw: &str) -> Option<Self> {
        let trimmed = raw.trim();
        for id in Self::ALL {
            if id.as_str().eq_ignore_ascii_case(trimmed) {
                return Some(id);
            }
        }
        None
    }
}

impl Default for ThemeId {
    fn default() -> Self {
        Self::Dark
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ThemeDefinition {
    pub id: ThemeId,
    pub id_str: &'static str,
    pub name_ru: &'static str,
    pub is_dark: bool,
    pub boot_bg: RgbaColor,
    pub boot_text: RgbaColor,
    pub preview_bg: RgbaColor,
    pub preview_surface: RgbaColor,
    pub preview_elevated: RgbaColor,
    pub preview_border: RgbaColor,
    pub preview_accent: RgbaColor,
    pub preview_accent_text: RgbaColor,
    pub preview_text: RgbaColor,
    // 43 base tokens
    pub bg_app: RgbaColor,
    pub bg_surface: RgbaColor,
    pub bg_elevated: RgbaColor,
    pub bg_hover: RgbaColor,
    pub bg_active: RgbaColor,
    pub bg_titlebar: RgbaColor,
    pub border_subtle: RgbaColor,
    pub border_strong: RgbaColor,
    pub border_input: RgbaColor,
    pub text_primary: RgbaColor,
    pub text_secondary: RgbaColor,
    pub text_muted: RgbaColor,
    pub accent_solid: RgbaColor,
    pub accent_solid_hover: RgbaColor,
    pub accent_solid_active: RgbaColor,
    pub accent_text: RgbaColor,
    pub accent_card_tint: RgbaColor,
    pub accent_soft: RgbaColor,
    pub accent_border: RgbaColor,
    pub status_active_text: RgbaColor,
    pub status_active_soft: RgbaColor,
    pub status_active_border: RgbaColor,
    pub status_warn_text: RgbaColor,
    pub status_warn_soft: RgbaColor,
    pub status_warn_border: RgbaColor,
    pub status_danger_solid: RgbaColor,
    pub status_danger_solid_hover: RgbaColor,
    pub status_danger_text: RgbaColor,
    pub status_danger_soft: RgbaColor,
    pub status_danger_border: RgbaColor,
    pub focus_ring: RgbaColor,
    pub switch_off_bg: RgbaColor,
    pub switch_off_border: RgbaColor,
    pub switch_off_thumb: RgbaColor,
    pub text_on_solid: RgbaColor,
    pub close_hover_bg: RgbaColor,
    pub close_active_bg: RgbaColor,
    pub backdrop_overlay: RgbaColor,
    pub shadow_card: ShadowSpec,
    pub shadow_card_hover: ShadowSpec,
    pub shadow_dialog: ShadowSpec,
    pub scrollbar_thumb: RgbaColor,
    pub scrollbar_thumb_hover: RgbaColor,
    // 2 optional enhancement tokens (themes 3, 4, 5, 8)
    pub bg_app_glow: Option<GlowSpec>,
    pub surface_top_highlight: Option<RgbaColor>,
}

const DARK_SHADOW_CARD: &[ShadowLayer] = &[ShadowLayer::new(
    0.0,
    1.0,
    2.0,
    0.0,
    RgbaColor::rgba("rgba(0,0,0,0.28)", 0, 0, 0, 0.28),
)];
const DARK_SHADOW_CARD_HOVER: &[ShadowLayer] = &[ShadowLayer::new(
    0.0,
    4.0,
    12.0,
    0.0,
    RgbaColor::rgba("rgba(0,0,0,0.36)", 0, 0, 0, 0.36),
)];
const DARK_SHADOW_DIALOG: &[ShadowLayer] = &[ShadowLayer::new(
    0.0,
    18.0,
    44.0,
    0.0,
    RgbaColor::rgba("rgba(0,0,0,0.62)", 0, 0, 0, 0.62),
)];

const OLED_SHADOW_CARD: &[ShadowLayer] = &[ShadowLayer::new(
    0.0,
    0.0,
    0.0,
    1.0,
    RgbaColor::rgba("rgba(255,255,255,0.02)", 255, 255, 255, 0.02),
)];
const OLED_SHADOW_CARD_HOVER: &[ShadowLayer] = &[ShadowLayer::new(
    0.0,
    4.0,
    16.0,
    0.0,
    RgbaColor::rgba("rgba(0,0,0,0.65)", 0, 0, 0, 0.65),
)];
const OLED_SHADOW_DIALOG: &[ShadowLayer] = &[ShadowLayer::new(
    0.0,
    20.0,
    56.0,
    0.0,
    RgbaColor::rgba("rgba(0,0,0,0.85)", 0, 0, 0, 0.85),
)];

const EMERALD_SHADOW_CARD: &[ShadowLayer] = &[ShadowLayer::new(
    0.0,
    1.0,
    2.0,
    0.0,
    RgbaColor::rgba("rgba(0,0,0,0.30)", 0, 0, 0, 0.30),
)];
const EMERALD_SHADOW_CARD_HOVER: &[ShadowLayer] = &[ShadowLayer::new(
    0.0,
    4.0,
    12.0,
    0.0,
    RgbaColor::rgba("rgba(0,0,0,0.40)", 0, 0, 0, 0.40),
)];
const EMERALD_SHADOW_DIALOG: &[ShadowLayer] = &[ShadowLayer::new(
    0.0,
    18.0,
    44.0,
    0.0,
    RgbaColor::rgba("rgba(0,0,0,0.65)", 0, 0, 0, 0.65),
)];

const GRAPHITE_SHADOW_CARD: &[ShadowLayer] = &[ShadowLayer::new(
    0.0,
    1.0,
    3.0,
    0.0,
    RgbaColor::rgba("rgba(0,0,0,0.26)", 0, 0, 0, 0.26),
)];
const GRAPHITE_SHADOW_CARD_HOVER: &[ShadowLayer] = &[ShadowLayer::new(
    0.0,
    4.0,
    12.0,
    0.0,
    RgbaColor::rgba("rgba(0,0,0,0.36)", 0, 0, 0, 0.36),
)];
const GRAPHITE_SHADOW_DIALOG: &[ShadowLayer] = &[ShadowLayer::new(
    0.0,
    18.0,
    44.0,
    0.0,
    RgbaColor::rgba("rgba(0,0,0,0.58)", 0, 0, 0, 0.58),
)];

const MIDNIGHT_SHADOW_CARD: &[ShadowLayer] = &[ShadowLayer::new(
    0.0,
    1.0,
    2.0,
    0.0,
    RgbaColor::rgba("rgba(0,0,0,0.32)", 0, 0, 0, 0.32),
)];
const MIDNIGHT_SHADOW_CARD_HOVER: &[ShadowLayer] = &[ShadowLayer::new(
    0.0,
    4.0,
    14.0,
    0.0,
    RgbaColor::rgba("rgba(0,0,0,0.42)", 0, 0, 0, 0.42),
)];
const MIDNIGHT_SHADOW_DIALOG: &[ShadowLayer] = &[ShadowLayer::new(
    0.0,
    18.0,
    46.0,
    0.0,
    RgbaColor::rgba("rgba(0,0,0,0.66)", 0, 0, 0, 0.66),
)];

const LIGHT_SHADOW_CARD: &[ShadowLayer] = &[
    ShadowLayer::new(
        0.0,
        1.0,
        3.0,
        0.0,
        RgbaColor::rgba("rgba(15,23,42,0.06)", 15, 23, 42, 0.06),
    ),
    ShadowLayer::new(
        0.0,
        1.0,
        2.0,
        0.0,
        RgbaColor::rgba("rgba(15,23,42,0.04)", 15, 23, 42, 0.04),
    ),
];
const LIGHT_SHADOW_CARD_HOVER: &[ShadowLayer] = &[ShadowLayer::new(
    0.0,
    4.0,
    12.0,
    0.0,
    RgbaColor::rgba("rgba(15,23,42,0.09)", 15, 23, 42, 0.09),
)];
const LIGHT_SHADOW_DIALOG: &[ShadowLayer] = &[ShadowLayer::new(
    0.0,
    20.0,
    44.0,
    0.0,
    RgbaColor::rgba("rgba(15,23,42,0.18)", 15, 23, 42, 0.18),
)];

const DAYLIGHT_SHADOW_CARD: &[ShadowLayer] = &[
    ShadowLayer::new(
        0.0,
        1.0,
        3.0,
        0.0,
        RgbaColor::rgba("rgba(31,28,23,0.06)", 31, 28, 23, 0.06),
    ),
    ShadowLayer::new(
        0.0,
        1.0,
        2.0,
        0.0,
        RgbaColor::rgba("rgba(31,28,23,0.04)", 31, 28, 23, 0.04),
    ),
];
const DAYLIGHT_SHADOW_CARD_HOVER: &[ShadowLayer] = &[ShadowLayer::new(
    0.0,
    4.0,
    12.0,
    0.0,
    RgbaColor::rgba("rgba(31,28,23,0.09)", 31, 28, 23, 0.09),
)];
const DAYLIGHT_SHADOW_DIALOG: &[ShadowLayer] = &[ShadowLayer::new(
    0.0,
    20.0,
    44.0,
    0.0,
    RgbaColor::rgba("rgba(31,28,23,0.18)", 31, 28, 23, 0.18),
)];

const FROST_SHADOW_CARD: &[ShadowLayer] = &[
    ShadowLayer::new(
        0.0,
        1.0,
        3.0,
        0.0,
        RgbaColor::rgba("rgba(20,30,48,0.06)", 20, 30, 48, 0.06),
    ),
    ShadowLayer::new(
        0.0,
        1.0,
        2.0,
        0.0,
        RgbaColor::rgba("rgba(20,30,48,0.04)", 20, 30, 48, 0.04),
    ),
];
const FROST_SHADOW_CARD_HOVER: &[ShadowLayer] = &[ShadowLayer::new(
    0.0,
    4.0,
    12.0,
    0.0,
    RgbaColor::rgba("rgba(20,30,48,0.10)", 20, 30, 48, 0.10),
)];
const FROST_SHADOW_DIALOG: &[ShadowLayer] = &[ShadowLayer::new(
    0.0,
    20.0,
    44.0,
    0.0,
    RgbaColor::rgba("rgba(20,30,48,0.19)", 20, 30, 48, 0.19),
)];

static THEMES: [ThemeDefinition; 8] = [
    // 1. dark — Тёмная классика
    ThemeDefinition {
        id: ThemeId::Dark,
        id_str: "dark",
        name_ru: "Тёмная классика",
        is_dark: true,
        boot_bg: RgbaColor::hex("#0c0f14", 0x0c, 0x0f, 0x14),
        boot_text: RgbaColor::hex("#f1f5f9", 0xf1, 0xf5, 0xf9),
        preview_bg: RgbaColor::hex("#0c0f14", 0x0c, 0x0f, 0x14),
        preview_surface: RgbaColor::hex("#131720", 0x13, 0x17, 0x20),
        preview_elevated: RgbaColor::hex("#1b202c", 0x1b, 0x20, 0x2c),
        preview_border: RgbaColor::hex("#242b38", 0x24, 0x2b, 0x38),
        preview_accent: RgbaColor::hex("#2563eb", 0x25, 0x63, 0xeb),
        preview_accent_text: RgbaColor::hex("#74b4fc", 0x74, 0xb4, 0xfc),
        preview_text: RgbaColor::hex("#f1f5f9", 0xf1, 0xf5, 0xf9),
        bg_app: RgbaColor::hex("#0c0f14", 0x0c, 0x0f, 0x14),
        bg_surface: RgbaColor::hex("#131720", 0x13, 0x17, 0x20),
        bg_elevated: RgbaColor::hex("#1b202c", 0x1b, 0x20, 0x2c),
        bg_hover: RgbaColor::hex("#232a38", 0x23, 0x2a, 0x38),
        bg_active: RgbaColor::hex("#2c3547", 0x2c, 0x35, 0x47),
        bg_titlebar: RgbaColor::rgba("rgba(12,15,20,0.94)", 12, 15, 20, 0.94),
        border_subtle: RgbaColor::hex("#242b38", 0x24, 0x2b, 0x38),
        border_strong: RgbaColor::hex("#374156", 0x37, 0x41, 0x56),
        border_input: RgbaColor::hex("#586884", 0x58, 0x68, 0x84),
        text_primary: RgbaColor::hex("#f1f5f9", 0xf1, 0xf5, 0xf9),
        text_secondary: RgbaColor::hex("#a3b3c9", 0xa3, 0xb3, 0xc9),
        text_muted: RgbaColor::hex("#8293ab", 0x82, 0x93, 0xab),
        accent_solid: RgbaColor::hex("#2563eb", 0x25, 0x63, 0xeb),
        accent_solid_hover: RgbaColor::hex("#1d4ed8", 0x1d, 0x4e, 0xd8),
        accent_solid_active: RgbaColor::hex("#1e40af", 0x1e, 0x40, 0xaf),
        accent_text: RgbaColor::hex("#74b4fc", 0x74, 0xb4, 0xfc),
        accent_card_tint: RgbaColor::rgba("rgba(59,130,246,0.08)", 59, 130, 246, 0.08),
        accent_soft: RgbaColor::rgba("rgba(59,130,246,0.15)", 59, 130, 246, 0.15),
        accent_border: RgbaColor::rgba("rgba(96,165,250,0.36)", 96, 165, 250, 0.36),
        status_active_text: RgbaColor::hex("#34d399", 0x34, 0xd3, 0x99),
        status_active_soft: RgbaColor::rgba("rgba(16,185,129,0.14)", 16, 185, 129, 0.14),
        status_active_border: RgbaColor::rgba("rgba(52,211,153,0.36)", 52, 211, 153, 0.36),
        status_warn_text: RgbaColor::hex("#fbbf24", 0xfb, 0xbf, 0x24),
        status_warn_soft: RgbaColor::rgba("rgba(245,158,11,0.14)", 245, 158, 11, 0.14),
        status_warn_border: RgbaColor::rgba("rgba(251,191,36,0.36)", 251, 191, 36, 0.36),
        status_danger_solid: RgbaColor::hex("#dc2626", 0xdc, 0x26, 0x26),
        status_danger_solid_hover: RgbaColor::hex("#b91c1c", 0xb9, 0x1c, 0x1c),
        status_danger_text: RgbaColor::hex("#f87171", 0xf8, 0x71, 0x71),
        status_danger_soft: RgbaColor::rgba("rgba(239,68,68,0.15)", 239, 68, 68, 0.15),
        status_danger_border: RgbaColor::rgba("rgba(248,113,113,0.38)", 248, 113, 113, 0.38),
        focus_ring: RgbaColor::hex("#60a5fa", 0x60, 0xa5, 0xfa),
        switch_off_bg: RgbaColor::hex("#252c3b", 0x25, 0x2c, 0x3b),
        switch_off_border: RgbaColor::hex("#586884", 0x58, 0x68, 0x84),
        switch_off_thumb: RgbaColor::hex("#cbd5e1", 0xcb, 0xd5, 0xe1),
        text_on_solid: RgbaColor::hex("#ffffff", 0xff, 0xff, 0xff),
        close_hover_bg: RgbaColor::hex("#c42b1c", 0xc4, 0x2b, 0x1c),
        close_active_bg: RgbaColor::hex("#9e2216", 0x9e, 0x22, 0x16),
        backdrop_overlay: RgbaColor::rgba("rgba(6,8,12,0.72)", 6, 8, 12, 0.72),
        shadow_card: ShadowSpec {
            layers: DARK_SHADOW_CARD,
            raw: "0 1px 2px rgba(0,0,0,0.28)",
        },
        shadow_card_hover: ShadowSpec {
            layers: DARK_SHADOW_CARD_HOVER,
            raw: "0 4px 12px rgba(0,0,0,0.36)",
        },
        shadow_dialog: ShadowSpec {
            layers: DARK_SHADOW_DIALOG,
            raw: "0 18px 44px rgba(0,0,0,0.62)",
        },
        scrollbar_thumb: RgbaColor::hex("#2e3748", 0x2e, 0x37, 0x48),
        scrollbar_thumb_hover: RgbaColor::hex("#46536b", 0x46, 0x53, 0x6b),
        bg_app_glow: None,
        surface_top_highlight: None,
    },
    // 2. oled-obsidian — OLED Обсидиан
    ThemeDefinition {
        id: ThemeId::OledObsidian,
        id_str: "oled-obsidian",
        name_ru: "OLED Обсидиан",
        is_dark: true,
        boot_bg: RgbaColor::hex("#000000", 0x00, 0x00, 0x00),
        boot_text: RgbaColor::hex("#f3f6fa", 0xf3, 0xf6, 0xfa),
        preview_bg: RgbaColor::hex("#000000", 0x00, 0x00, 0x00),
        preview_surface: RgbaColor::hex("#090b0f", 0x09, 0x0b, 0x0f),
        preview_elevated: RgbaColor::hex("#11151d", 0x11, 0x15, 0x1d),
        preview_border: RgbaColor::hex("#1c222e", 0x1c, 0x22, 0x2e),
        preview_accent: RgbaColor::hex("#0275a6", 0x02, 0x75, 0xa6),
        preview_accent_text: RgbaColor::hex("#4cc4fa", 0x4c, 0xc4, 0xfa),
        preview_text: RgbaColor::hex("#f3f6fa", 0xf3, 0xf6, 0xfa),
        bg_app: RgbaColor::hex("#000000", 0x00, 0x00, 0x00),
        bg_surface: RgbaColor::hex("#090b0f", 0x09, 0x0b, 0x0f),
        bg_elevated: RgbaColor::hex("#11151d", 0x11, 0x15, 0x1d),
        bg_hover: RgbaColor::hex("#191f2b", 0x19, 0x1f, 0x2b),
        bg_active: RgbaColor::hex("#222a3a", 0x22, 0x2a, 0x3a),
        bg_titlebar: RgbaColor::rgba("rgba(0,0,0,0.96)", 0, 0, 0, 0.96),
        border_subtle: RgbaColor::hex("#1c222e", 0x1c, 0x22, 0x2e),
        border_strong: RgbaColor::hex("#2e3748", 0x2e, 0x37, 0x48),
        border_input: RgbaColor::hex("#51607a", 0x51, 0x60, 0x7a),
        text_primary: RgbaColor::hex("#f3f6fa", 0xf3, 0xf6, 0xfa),
        text_secondary: RgbaColor::hex("#9fb0c5", 0x9f, 0xb0, 0xc5),
        text_muted: RgbaColor::hex("#7d8ea6", 0x7d, 0x8e, 0xa6),
        accent_solid: RgbaColor::hex("#0275a6", 0x02, 0x75, 0xa6),
        accent_solid_hover: RgbaColor::hex("#03628c", 0x03, 0x62, 0x8c),
        accent_solid_active: RgbaColor::hex("#065173", 0x06, 0x51, 0x73),
        accent_text: RgbaColor::hex("#4cc4fa", 0x4c, 0xc4, 0xfa),
        accent_card_tint: RgbaColor::rgba("rgba(56,189,248,0.07)", 56, 189, 248, 0.07),
        accent_soft: RgbaColor::rgba("rgba(56,189,248,0.14)", 56, 189, 248, 0.14),
        accent_border: RgbaColor::rgba("rgba(56,189,248,0.36)", 56, 189, 248, 0.36),
        status_active_text: RgbaColor::hex("#34d399", 0x34, 0xd3, 0x99),
        status_active_soft: RgbaColor::rgba("rgba(16,185,129,0.13)", 16, 185, 129, 0.13),
        status_active_border: RgbaColor::rgba("rgba(52,211,153,0.36)", 52, 211, 153, 0.36),
        status_warn_text: RgbaColor::hex("#fbbf24", 0xfb, 0xbf, 0x24),
        status_warn_soft: RgbaColor::rgba("rgba(245,158,11,0.13)", 245, 158, 11, 0.13),
        status_warn_border: RgbaColor::rgba("rgba(251,191,36,0.36)", 251, 191, 36, 0.36),
        status_danger_solid: RgbaColor::hex("#d42636", 0xd4, 0x26, 0x36),
        status_danger_solid_hover: RgbaColor::hex("#b31e2c", 0xb3, 0x1e, 0x2c),
        status_danger_text: RgbaColor::hex("#fb7185", 0xfb, 0x71, 0x85),
        status_danger_soft: RgbaColor::rgba("rgba(244,63,94,0.14)", 244, 63, 94, 0.14),
        status_danger_border: RgbaColor::rgba("rgba(251,113,133,0.38)", 251, 113, 133, 0.38),
        focus_ring: RgbaColor::hex("#38bdf8", 0x38, 0xbd, 0xf8),
        switch_off_bg: RgbaColor::hex("#181d27", 0x18, 0x1d, 0x27),
        switch_off_border: RgbaColor::hex("#51607a", 0x51, 0x60, 0x7a),
        switch_off_thumb: RgbaColor::hex("#cbd5e1", 0xcb, 0xd5, 0xe1),
        text_on_solid: RgbaColor::hex("#ffffff", 0xff, 0xff, 0xff),
        close_hover_bg: RgbaColor::hex("#c42b1c", 0xc4, 0x2b, 0x1c),
        close_active_bg: RgbaColor::hex("#9e2216", 0x9e, 0x22, 0x16),
        backdrop_overlay: RgbaColor::rgba("rgba(0,0,0,0.80)", 0, 0, 0, 0.80),
        shadow_card: ShadowSpec {
            layers: OLED_SHADOW_CARD,
            raw: "0 0 0 1px rgba(255,255,255,0.02)",
        },
        shadow_card_hover: ShadowSpec {
            layers: OLED_SHADOW_CARD_HOVER,
            raw: "0 4px 16px rgba(0,0,0,0.65)",
        },
        shadow_dialog: ShadowSpec {
            layers: OLED_SHADOW_DIALOG,
            raw: "0 20px 56px rgba(0,0,0,0.85)",
        },
        scrollbar_thumb: RgbaColor::hex("#252d3b", 0x25, 0x2d, 0x3b),
        scrollbar_thumb_hover: RgbaColor::hex("#3d495e", 0x3d, 0x49, 0x5e),
        bg_app_glow: None,
        surface_top_highlight: None,
    },
    // 3. emerald-ops — Тактический изумруд
    ThemeDefinition {
        id: ThemeId::EmeraldOps,
        id_str: "emerald-ops",
        name_ru: "Тактический изумруд",
        is_dark: true,
        boot_bg: RgbaColor::hex("#090e0d", 0x09, 0x0e, 0x0d),
        boot_text: RgbaColor::hex("#edf6f2", 0xed, 0xf6, 0xf2),
        preview_bg: RgbaColor::hex("#090e0d", 0x09, 0x0e, 0x0d),
        preview_surface: RgbaColor::hex("#101715", 0x10, 0x17, 0x15),
        preview_elevated: RgbaColor::hex("#17221f", 0x17, 0x22, 0x1f),
        preview_border: RgbaColor::hex("#202e2a", 0x20, 0x2e, 0x2a),
        preview_accent: RgbaColor::hex("#0e7478", 0x0e, 0x74, 0x78),
        preview_accent_text: RgbaColor::hex("#3ddbe0", 0x3d, 0xdb, 0xe0),
        preview_text: RgbaColor::hex("#edf6f2", 0xed, 0xf6, 0xf2),
        bg_app: RgbaColor::hex("#090e0d", 0x09, 0x0e, 0x0d),
        bg_surface: RgbaColor::hex("#101715", 0x10, 0x17, 0x15),
        bg_elevated: RgbaColor::hex("#17221f", 0x17, 0x22, 0x1f),
        bg_hover: RgbaColor::hex("#1f2e2a", 0x1f, 0x2e, 0x2a),
        bg_active: RgbaColor::hex("#283b36", 0x28, 0x3b, 0x36),
        bg_titlebar: RgbaColor::rgba("rgba(9,14,13,0.94)", 9, 14, 13, 0.94),
        border_subtle: RgbaColor::hex("#202e2a", 0x20, 0x2e, 0x2a),
        border_strong: RgbaColor::hex("#324741", 0x32, 0x47, 0x41),
        border_input: RgbaColor::hex("#507268", 0x50, 0x72, 0x68),
        text_primary: RgbaColor::hex("#edf6f2", 0xed, 0xf6, 0xf2),
        text_secondary: RgbaColor::hex("#9eb9b0", 0x9e, 0xb9, 0xb0),
        text_muted: RgbaColor::hex("#7f9e93", 0x7f, 0x9e, 0x93),
        accent_solid: RgbaColor::hex("#0e7478", 0x0e, 0x74, 0x78),
        accent_solid_hover: RgbaColor::hex("#0c6266", 0x0c, 0x62, 0x66),
        accent_solid_active: RgbaColor::hex("#105356", 0x10, 0x53, 0x56),
        accent_text: RgbaColor::hex("#3ddbe0", 0x3d, 0xdb, 0xe0),
        accent_card_tint: RgbaColor::rgba("rgba(45,212,212,0.07)", 45, 212, 212, 0.07),
        accent_soft: RgbaColor::rgba("rgba(20,184,184,0.15)", 20, 184, 184, 0.15),
        accent_border: RgbaColor::rgba("rgba(61,219,224,0.36)", 61, 219, 224, 0.36),
        status_active_text: RgbaColor::hex("#65e67d", 0x65, 0xe6, 0x7d),
        status_active_soft: RgbaColor::rgba("rgba(34,197,94,0.14)", 34, 197, 94, 0.14),
        status_active_border: RgbaColor::rgba("rgba(101,230,125,0.35)", 101, 230, 125, 0.35),
        status_warn_text: RgbaColor::hex("#fbbf24", 0xfb, 0xbf, 0x24),
        status_warn_soft: RgbaColor::rgba("rgba(245,158,11,0.14)", 245, 158, 11, 0.14),
        status_warn_border: RgbaColor::rgba("rgba(251,191,36,0.35)", 251, 191, 36, 0.35),
        status_danger_solid: RgbaColor::hex("#d62839", 0xd6, 0x28, 0x39),
        status_danger_solid_hover: RgbaColor::hex("#b51f2e", 0xb5, 0x1f, 0x2e),
        status_danger_text: RgbaColor::hex("#fb7185", 0xfb, 0x71, 0x85),
        status_danger_soft: RgbaColor::rgba("rgba(244,63,94,0.15)", 244, 63, 94, 0.15),
        status_danger_border: RgbaColor::rgba("rgba(251,113,133,0.38)", 251, 113, 133, 0.38),
        focus_ring: RgbaColor::hex("#3ddbe0", 0x3d, 0xdb, 0xe0),
        switch_off_bg: RgbaColor::hex("#1d2a26", 0x1d, 0x2a, 0x26),
        switch_off_border: RgbaColor::hex("#507268", 0x50, 0x72, 0x68),
        switch_off_thumb: RgbaColor::hex("#c5dbd3", 0xc5, 0xdb, 0xd3),
        text_on_solid: RgbaColor::hex("#ffffff", 0xff, 0xff, 0xff),
        close_hover_bg: RgbaColor::hex("#c42b1c", 0xc4, 0x2b, 0x1c),
        close_active_bg: RgbaColor::hex("#9e2216", 0x9e, 0x22, 0x16),
        backdrop_overlay: RgbaColor::rgba("rgba(4,9,8,0.74)", 4, 9, 8, 0.74),
        shadow_card: ShadowSpec {
            layers: EMERALD_SHADOW_CARD,
            raw: "0 1px 2px rgba(0,0,0,0.30)",
        },
        shadow_card_hover: ShadowSpec {
            layers: EMERALD_SHADOW_CARD_HOVER,
            raw: "0 4px 12px rgba(0,0,0,0.40)",
        },
        shadow_dialog: ShadowSpec {
            layers: EMERALD_SHADOW_DIALOG,
            raw: "0 18px 44px rgba(0,0,0,0.65)",
        },
        scrollbar_thumb: RgbaColor::hex("#293a35", 0x29, 0x3a, 0x35),
        scrollbar_thumb_hover: RgbaColor::hex("#3d564e", 0x3d, 0x56, 0x4e),
        bg_app_glow: Some(GlowSpec {
            rx_px: 700.0,
            ry_px: 260.0,
            cx_pct: 18.0,
            cy_pct: 0.0,
            color: RgbaColor::rgba("rgba(20,184,184,0.065)", 20, 184, 184, 0.065),
            stop_pct: 70.0,
            raw: "radial-gradient(700px 260px at 18% 0%, rgba(20,184,184,0.065), transparent 70%)",
        }),
        surface_top_highlight: Some(RgbaColor::rgba(
            "rgba(61,219,224,0.08)",
            61,
            219,
            224,
            0.08,
        )),
    },
    // 4. graphite-amber — Спокойный графит
    ThemeDefinition {
        id: ThemeId::GraphiteAmber,
        id_str: "graphite-amber",
        name_ru: "Спокойный графит",
        is_dark: true,
        boot_bg: RgbaColor::hex("#141518", 0x14, 0x15, 0x18),
        boot_text: RgbaColor::hex("#f3f1ec", 0xf3, 0xf1, 0xec),
        preview_bg: RgbaColor::hex("#141518", 0x14, 0x15, 0x18),
        preview_surface: RgbaColor::hex("#1b1d21", 0x1b, 0x1d, 0x21),
        preview_elevated: RgbaColor::hex("#24272d", 0x24, 0x27, 0x2d),
        preview_border: RgbaColor::hex("#2c3037", 0x2c, 0x30, 0x37),
        preview_accent: RgbaColor::hex("#c2410c", 0xc2, 0x41, 0x0c),
        preview_accent_text: RgbaColor::hex("#fb9b52", 0xfb, 0x9b, 0x52),
        preview_text: RgbaColor::hex("#f3f1ec", 0xf3, 0xf1, 0xec),
        bg_app: RgbaColor::hex("#141518", 0x14, 0x15, 0x18),
        bg_surface: RgbaColor::hex("#1b1d21", 0x1b, 0x1d, 0x21),
        bg_elevated: RgbaColor::hex("#24272d", 0x24, 0x27, 0x2d),
        bg_hover: RgbaColor::hex("#2d3139", 0x2d, 0x31, 0x39),
        bg_active: RgbaColor::hex("#373c46", 0x37, 0x3c, 0x46),
        bg_titlebar: RgbaColor::rgba("rgba(20,21,24,0.95)", 20, 21, 24, 0.95),
        border_subtle: RgbaColor::hex("#2c3037", 0x2c, 0x30, 0x37),
        border_strong: RgbaColor::hex("#40454f", 0x40, 0x45, 0x4f),
        border_input: RgbaColor::hex("#636b7a", 0x63, 0x6b, 0x7a),
        text_primary: RgbaColor::hex("#f3f1ec", 0xf3, 0xf1, 0xec),
        text_secondary: RgbaColor::hex("#b5b2aa", 0xb5, 0xb2, 0xaa),
        text_muted: RgbaColor::hex("#98958d", 0x98, 0x95, 0x8d),
        accent_solid: RgbaColor::hex("#c2410c", 0xc2, 0x41, 0x0c),
        accent_solid_hover: RgbaColor::hex("#a8370a", 0xa8, 0x37, 0x0a),
        accent_solid_active: RgbaColor::hex("#8f2e08", 0x8f, 0x2e, 0x08),
        accent_text: RgbaColor::hex("#fb9b52", 0xfb, 0x9b, 0x52),
        accent_card_tint: RgbaColor::rgba("rgba(249,115,22,0.08)", 249, 115, 22, 0.08),
        accent_soft: RgbaColor::rgba("rgba(249,115,22,0.15)", 249, 115, 22, 0.15),
        accent_border: RgbaColor::rgba("rgba(251,155,82,0.38)", 251, 155, 82, 0.38),
        status_active_text: RgbaColor::hex("#4ade80", 0x4a, 0xde, 0x80),
        status_active_soft: RgbaColor::rgba("rgba(34,197,94,0.14)", 34, 197, 94, 0.14),
        status_active_border: RgbaColor::rgba("rgba(74,222,128,0.35)", 74, 222, 128, 0.35),
        status_warn_text: RgbaColor::hex("#fdeb5b", 0xfd, 0xeb, 0x5b),
        status_warn_soft: RgbaColor::rgba("rgba(250,204,21,0.13)", 250, 204, 21, 0.13),
        status_warn_border: RgbaColor::rgba("rgba(253,235,91,0.35)", 253, 235, 91, 0.35),
        status_danger_solid: RgbaColor::hex("#cf253c", 0xcf, 0x25, 0x3c),
        status_danger_solid_hover: RgbaColor::hex("#b01d31", 0xb0, 0x1d, 0x31),
        status_danger_text: RgbaColor::hex("#fb7185", 0xfb, 0x71, 0x85),
        status_danger_soft: RgbaColor::rgba("rgba(244,63,94,0.15)", 244, 63, 94, 0.15),
        status_danger_border: RgbaColor::rgba("rgba(251,113,133,0.38)", 251, 113, 133, 0.38),
        focus_ring: RgbaColor::hex("#fb9b52", 0xfb, 0x9b, 0x52),
        switch_off_bg: RgbaColor::hex("#2b2f37", 0x2b, 0x2f, 0x37),
        switch_off_border: RgbaColor::hex("#636b7a", 0x63, 0x6b, 0x7a),
        switch_off_thumb: RgbaColor::hex("#d6d3cd", 0xd6, 0xd3, 0xcd),
        text_on_solid: RgbaColor::hex("#ffffff", 0xff, 0xff, 0xff),
        close_hover_bg: RgbaColor::hex("#c42b1c", 0xc4, 0x2b, 0x1c),
        close_active_bg: RgbaColor::hex("#9e2216", 0x9e, 0x22, 0x16),
        backdrop_overlay: RgbaColor::rgba("rgba(10,11,13,0.72)", 10, 11, 13, 0.72),
        shadow_card: ShadowSpec {
            layers: GRAPHITE_SHADOW_CARD,
            raw: "0 1px 3px rgba(0,0,0,0.26)",
        },
        shadow_card_hover: ShadowSpec {
            layers: GRAPHITE_SHADOW_CARD_HOVER,
            raw: "0 4px 12px rgba(0,0,0,0.36)",
        },
        shadow_dialog: ShadowSpec {
            layers: GRAPHITE_SHADOW_DIALOG,
            raw: "0 18px 44px rgba(0,0,0,0.58)",
        },
        scrollbar_thumb: RgbaColor::hex("#383d47", 0x38, 0x3d, 0x47),
        scrollbar_thumb_hover: RgbaColor::hex("#505766", 0x50, 0x57, 0x66),
        bg_app_glow: Some(GlowSpec {
            rx_px: 700.0,
            ry_px: 260.0,
            cx_pct: 82.0,
            cy_pct: 0.0,
            color: RgbaColor::rgba("rgba(249,115,22,0.055)", 249, 115, 22, 0.055),
            stop_pct: 70.0,
            raw: "radial-gradient(700px 260px at 82% 0%, rgba(249,115,22,0.055), transparent 70%)",
        }),
        surface_top_highlight: Some(RgbaColor::rgba(
            "rgba(251,155,82,0.07)",
            251,
            155,
            82,
            0.07,
        )),
    },
    // 5. midnight-violet — Глубокая ночь
    ThemeDefinition {
        id: ThemeId::MidnightViolet,
        id_str: "midnight-violet",
        name_ru: "Глубокая ночь",
        is_dark: true,
        boot_bg: RgbaColor::hex("#0d0c16", 0x0d, 0x0c, 0x16),
        boot_text: RgbaColor::hex("#f3f1fc", 0xf3, 0xf1, 0xfc),
        preview_bg: RgbaColor::hex("#0d0c16", 0x0d, 0x0c, 0x16),
        preview_surface: RgbaColor::hex("#151324", 0x15, 0x13, 0x24),
        preview_elevated: RgbaColor::hex("#1f1c33", 0x1f, 0x1c, 0x33),
        preview_border: RgbaColor::hex("#292542", 0x29, 0x25, 0x42),
        preview_accent: RgbaColor::hex("#7c3aed", 0x7c, 0x3a, 0xed),
        preview_accent_text: RgbaColor::hex("#c4a8fd", 0xc4, 0xa8, 0xfd),
        preview_text: RgbaColor::hex("#f3f1fc", 0xf3, 0xf1, 0xfc),
        bg_app: RgbaColor::hex("#0d0c16", 0x0d, 0x0c, 0x16),
        bg_surface: RgbaColor::hex("#151324", 0x15, 0x13, 0x24),
        bg_elevated: RgbaColor::hex("#1f1c33", 0x1f, 0x1c, 0x33),
        bg_hover: RgbaColor::hex("#282442", 0x28, 0x24, 0x42),
        bg_active: RgbaColor::hex("#322d52", 0x32, 0x2d, 0x52),
        bg_titlebar: RgbaColor::rgba("rgba(13,12,22,0.94)", 13, 12, 22, 0.94),
        border_subtle: RgbaColor::hex("#292542", 0x29, 0x25, 0x42),
        border_strong: RgbaColor::hex("#3d3761", 0x3d, 0x37, 0x61),
        border_input: RgbaColor::hex("#68609c", 0x68, 0x60, 0x9c),
        text_primary: RgbaColor::hex("#f3f1fc", 0xf3, 0xf1, 0xfc),
        text_secondary: RgbaColor::hex("#b0aad0", 0xb0, 0xaa, 0xd0),
        text_muted: RgbaColor::hex("#928cb4", 0x92, 0x8c, 0xb4),
        accent_solid: RgbaColor::hex("#7c3aed", 0x7c, 0x3a, 0xed),
        accent_solid_hover: RgbaColor::hex("#6d28d9", 0x6d, 0x28, 0xd9),
        accent_solid_active: RgbaColor::hex("#5b21b6", 0x5b, 0x21, 0xb6),
        accent_text: RgbaColor::hex("#c4a8fd", 0xc4, 0xa8, 0xfd),
        accent_card_tint: RgbaColor::rgba("rgba(139,92,246,0.09)", 139, 92, 246, 0.09),
        accent_soft: RgbaColor::rgba("rgba(139,92,246,0.16)", 139, 92, 246, 0.16),
        accent_border: RgbaColor::rgba("rgba(167,139,250,0.38)", 167, 139, 250, 0.38),
        status_active_text: RgbaColor::hex("#34d399", 0x34, 0xd3, 0x99),
        status_active_soft: RgbaColor::rgba("rgba(16,185,129,0.14)", 16, 185, 129, 0.14),
        status_active_border: RgbaColor::rgba("rgba(52,211,153,0.36)", 52, 211, 153, 0.36),
        status_warn_text: RgbaColor::hex("#fbbf24", 0xfb, 0xbf, 0x24),
        status_warn_soft: RgbaColor::rgba("rgba(245,158,11,0.14)", 245, 158, 11, 0.14),
        status_warn_border: RgbaColor::rgba("rgba(251,191,36,0.36)", 251, 191, 36, 0.36),
        status_danger_solid: RgbaColor::hex("#d62246", 0xd6, 0x22, 0x46),
        status_danger_solid_hover: RgbaColor::hex("#b51b3a", 0xb5, 0x1b, 0x3a),
        status_danger_text: RgbaColor::hex("#fb7185", 0xfb, 0x71, 0x85),
        status_danger_soft: RgbaColor::rgba("rgba(244,63,94,0.15)", 244, 63, 94, 0.15),
        status_danger_border: RgbaColor::rgba("rgba(251,113,133,0.38)", 251, 113, 133, 0.38),
        focus_ring: RgbaColor::hex("#a78bfa", 0xa7, 0x8b, 0xfa),
        switch_off_bg: RgbaColor::hex("#24203b", 0x24, 0x20, 0x3b),
        switch_off_border: RgbaColor::hex("#68609c", 0x68, 0x60, 0x9c),
        switch_off_thumb: RgbaColor::hex("#d4cff0", 0xd4, 0xcf, 0xf0),
        text_on_solid: RgbaColor::hex("#ffffff", 0xff, 0xff, 0xff),
        close_hover_bg: RgbaColor::hex("#c42b1c", 0xc4, 0x2b, 0x1c),
        close_active_bg: RgbaColor::hex("#9e2216", 0x9e, 0x22, 0x16),
        backdrop_overlay: RgbaColor::rgba("rgba(6,5,12,0.74)", 6, 5, 12, 0.74),
        shadow_card: ShadowSpec {
            layers: MIDNIGHT_SHADOW_CARD,
            raw: "0 1px 2px rgba(0,0,0,0.32)",
        },
        shadow_card_hover: ShadowSpec {
            layers: MIDNIGHT_SHADOW_CARD_HOVER,
            raw: "0 4px 14px rgba(0,0,0,0.42)",
        },
        shadow_dialog: ShadowSpec {
            layers: MIDNIGHT_SHADOW_DIALOG,
            raw: "0 18px 46px rgba(0,0,0,0.66)",
        },
        scrollbar_thumb: RgbaColor::hex("#332e52", 0x33, 0x2e, 0x52),
        scrollbar_thumb_hover: RgbaColor::hex("#4b4475", 0x4b, 0x44, 0x75),
        bg_app_glow: Some(GlowSpec {
            rx_px: 720.0,
            ry_px: 280.0,
            cx_pct: 50.0,
            cy_pct: 0.0,
            color: RgbaColor::rgba("rgba(139,92,246,0.085)", 139, 92, 246, 0.085),
            stop_pct: 72.0,
            raw: "radial-gradient(720px 280px at 50% 0%, rgba(139,92,246,0.085), transparent 72%)",
        }),
        surface_top_highlight: Some(RgbaColor::rgba(
            "rgba(196,168,253,0.09)",
            196,
            168,
            253,
            0.09,
        )),
    },
    // 6. light — Светлая классика
    ThemeDefinition {
        id: ThemeId::Light,
        id_str: "light",
        name_ru: "Светлая классика",
        is_dark: false,
        boot_bg: RgbaColor::hex("#f3f6fa", 0xf3, 0xf6, 0xfa),
        boot_text: RgbaColor::hex("#0f172a", 0x0f, 0x17, 0x2a),
        preview_bg: RgbaColor::hex("#f3f6fa", 0xf3, 0xf6, 0xfa),
        preview_surface: RgbaColor::hex("#ffffff", 0xff, 0xff, 0xff),
        preview_elevated: RgbaColor::hex("#edf2f7", 0xed, 0xf2, 0xf7),
        preview_border: RgbaColor::hex("#dce4ee", 0xdc, 0xe4, 0xee),
        preview_accent: RgbaColor::hex("#2563eb", 0x25, 0x63, 0xeb),
        preview_accent_text: RgbaColor::hex("#1d4ed8", 0x1d, 0x4e, 0xd8),
        preview_text: RgbaColor::hex("#0f172a", 0x0f, 0x17, 0x2a),
        bg_app: RgbaColor::hex("#f3f6fa", 0xf3, 0xf6, 0xfa),
        bg_surface: RgbaColor::hex("#ffffff", 0xff, 0xff, 0xff),
        bg_elevated: RgbaColor::hex("#edf2f7", 0xed, 0xf2, 0xf7),
        bg_hover: RgbaColor::hex("#e2e9f2", 0xe2, 0xe9, 0xf2),
        bg_active: RgbaColor::hex("#d4dfec", 0xd4, 0xdf, 0xec),
        bg_titlebar: RgbaColor::rgba("rgba(243,246,250,0.94)", 243, 246, 250, 0.94),
        border_subtle: RgbaColor::hex("#dce4ee", 0xdc, 0xe4, 0xee),
        border_strong: RgbaColor::hex("#becad9", 0xbe, 0xca, 0xd9),
        border_input: RgbaColor::hex("#7a8da6", 0x7a, 0x8d, 0xa6),
        text_primary: RgbaColor::hex("#0f172a", 0x0f, 0x17, 0x2a),
        text_secondary: RgbaColor::hex("#3d4d63", 0x3d, 0x4d, 0x63),
        text_muted: RgbaColor::hex("#56677e", 0x56, 0x67, 0x7e),
        accent_solid: RgbaColor::hex("#2563eb", 0x25, 0x63, 0xeb),
        accent_solid_hover: RgbaColor::hex("#1d4ed8", 0x1d, 0x4e, 0xd8),
        accent_solid_active: RgbaColor::hex("#1e40af", 0x1e, 0x40, 0xaf),
        accent_text: RgbaColor::hex("#1d4ed8", 0x1d, 0x4e, 0xd8),
        accent_card_tint: RgbaColor::rgba("rgba(37,99,235,0.05)", 37, 99, 235, 0.05),
        accent_soft: RgbaColor::rgba("rgba(37,99,235,0.10)", 37, 99, 235, 0.10),
        accent_border: RgbaColor::rgba("rgba(37,99,235,0.30)", 37, 99, 235, 0.30),
        status_active_text: RgbaColor::hex("#046c4e", 0x04, 0x6c, 0x4e),
        status_active_soft: RgbaColor::rgba("rgba(5,150,105,0.10)", 5, 150, 105, 0.10),
        status_active_border: RgbaColor::rgba("rgba(5,150,105,0.32)", 5, 150, 105, 0.32),
        status_warn_text: RgbaColor::hex("#8c4a08", 0x8c, 0x4a, 0x08),
        status_warn_soft: RgbaColor::rgba("rgba(217,119,6,0.11)", 217, 119, 6, 0.11),
        status_warn_border: RgbaColor::rgba("rgba(180,83,9,0.32)", 180, 83, 9, 0.32),
        status_danger_solid: RgbaColor::hex("#c81e1e", 0xc8, 0x1e, 0x1e),
        status_danger_solid_hover: RgbaColor::hex("#a61818", 0xa6, 0x18, 0x18),
        status_danger_text: RgbaColor::hex("#b91c1c", 0xb9, 0x1c, 0x1c),
        status_danger_soft: RgbaColor::rgba("rgba(220,38,38,0.09)", 220, 38, 38, 0.09),
        status_danger_border: RgbaColor::rgba("rgba(220,38,38,0.30)", 220, 38, 38, 0.30),
        focus_ring: RgbaColor::hex("#2563eb", 0x25, 0x63, 0xeb),
        switch_off_bg: RgbaColor::hex("#d8e1ec", 0xd8, 0xe1, 0xec),
        switch_off_border: RgbaColor::hex("#7a8da6", 0x7a, 0x8d, 0xa6),
        switch_off_thumb: RgbaColor::hex("#475569", 0x47, 0x55, 0x69),
        text_on_solid: RgbaColor::hex("#ffffff", 0xff, 0xff, 0xff),
        close_hover_bg: RgbaColor::hex("#c42b1c", 0xc4, 0x2b, 0x1c),
        close_active_bg: RgbaColor::hex("#9e2216", 0x9e, 0x22, 0x16),
        backdrop_overlay: RgbaColor::rgba("rgba(15,23,42,0.38)", 15, 23, 42, 0.38),
        shadow_card: ShadowSpec {
            layers: LIGHT_SHADOW_CARD,
            raw: "0 1px 3px rgba(15,23,42,0.06), 0 1px 2px rgba(15,23,42,0.04)",
        },
        shadow_card_hover: ShadowSpec {
            layers: LIGHT_SHADOW_CARD_HOVER,
            raw: "0 4px 12px rgba(15,23,42,0.09)",
        },
        shadow_dialog: ShadowSpec {
            layers: LIGHT_SHADOW_DIALOG,
            raw: "0 20px 44px rgba(15,23,42,0.18)",
        },
        scrollbar_thumb: RgbaColor::hex("#c2cedc", 0xc2, 0xce, 0xdc),
        scrollbar_thumb_hover: RgbaColor::hex("#94a6bd", 0x94, 0xa6, 0xbd),
        bg_app_glow: None,
        surface_top_highlight: None,
    },
    // 7. daylight-warm — Тёплая дневная
    ThemeDefinition {
        id: ThemeId::DaylightWarm,
        id_str: "daylight-warm",
        name_ru: "Тёплая дневная",
        is_dark: false,
        boot_bg: RgbaColor::hex("#f3efe6", 0xf3, 0xef, 0xe6),
        boot_text: RgbaColor::hex("#1f1c17", 0x1f, 0x1c, 0x17),
        preview_bg: RgbaColor::hex("#f3efe6", 0xf3, 0xef, 0xe6),
        preview_surface: RgbaColor::hex("#fbf9f4", 0xfb, 0xf9, 0xf4),
        preview_elevated: RgbaColor::hex("#ece6da", 0xec, 0xe6, 0xda),
        preview_border: RgbaColor::hex("#ddd5c6", 0xdd, 0xd5, 0xc6),
        preview_accent: RgbaColor::hex("#0b6e73", 0x0b, 0x6e, 0x73),
        preview_accent_text: RgbaColor::hex("#096166", 0x09, 0x61, 0x66),
        preview_text: RgbaColor::hex("#1f1c17", 0x1f, 0x1c, 0x17),
        bg_app: RgbaColor::hex("#f3efe6", 0xf3, 0xef, 0xe6),
        bg_surface: RgbaColor::hex("#fbf9f4", 0xfb, 0xf9, 0xf4),
        bg_elevated: RgbaColor::hex("#ece6da", 0xec, 0xe6, 0xda),
        bg_hover: RgbaColor::hex("#e2dacb", 0xe2, 0xda, 0xcb),
        bg_active: RgbaColor::hex("#d5cbb8", 0xd5, 0xcb, 0xb8),
        bg_titlebar: RgbaColor::rgba("rgba(243,239,230,0.95)", 243, 239, 230, 0.95),
        border_subtle: RgbaColor::hex("#ddd5c6", 0xdd, 0xd5, 0xc6),
        border_strong: RgbaColor::hex("#c0b49e", 0xc0, 0xb4, 0x9e),
        border_input: RgbaColor::hex("#8e826d", 0x8e, 0x82, 0x6d),
        text_primary: RgbaColor::hex("#1f1c17", 0x1f, 0x1c, 0x17),
        text_secondary: RgbaColor::hex("#4a4338", 0x4a, 0x43, 0x38),
        text_muted: RgbaColor::hex("#61594b", 0x61, 0x59, 0x4b),
        accent_solid: RgbaColor::hex("#0b6e73", 0x0b, 0x6e, 0x73),
        accent_solid_hover: RgbaColor::hex("#09595d", 0x09, 0x59, 0x5d),
        accent_solid_active: RgbaColor::hex("#08484b", 0x08, 0x48, 0x4b),
        accent_text: RgbaColor::hex("#096166", 0x09, 0x61, 0x66),
        accent_card_tint: RgbaColor::rgba("rgba(11,110,115,0.06)", 11, 110, 115, 0.06),
        accent_soft: RgbaColor::rgba("rgba(11,110,115,0.11)", 11, 110, 115, 0.11),
        accent_border: RgbaColor::rgba("rgba(11,110,115,0.30)", 11, 110, 115, 0.30),
        status_active_text: RgbaColor::hex("#1b6628", 0x1b, 0x66, 0x28),
        status_active_soft: RgbaColor::rgba("rgba(22,163,74,0.10)", 22, 163, 74, 0.10),
        status_active_border: RgbaColor::rgba("rgba(22,163,74,0.32)", 22, 163, 74, 0.32),
        status_warn_text: RgbaColor::hex("#8a4706", 0x8a, 0x47, 0x06),
        status_warn_soft: RgbaColor::rgba("rgba(217,119,6,0.11)", 217, 119, 6, 0.11),
        status_warn_border: RgbaColor::rgba("rgba(180,83,9,0.32)", 180, 83, 9, 0.32),
        status_danger_solid: RgbaColor::hex("#c2252d", 0xc2, 0x25, 0x2d),
        status_danger_solid_hover: RgbaColor::hex("#a11c23", 0xa1, 0x1c, 0x23),
        status_danger_text: RgbaColor::hex("#ad1c24", 0xad, 0x1c, 0x24),
        status_danger_soft: RgbaColor::rgba("rgba(220,38,38,0.09)", 220, 38, 38, 0.09),
        status_danger_border: RgbaColor::rgba("rgba(220,38,38,0.30)", 220, 38, 38, 0.30),
        focus_ring: RgbaColor::hex("#0b6e73", 0x0b, 0x6e, 0x73),
        switch_off_bg: RgbaColor::hex("#dad2c3", 0xda, 0xd2, 0xc3),
        switch_off_border: RgbaColor::hex("#8e826d", 0x8e, 0x82, 0x6d),
        switch_off_thumb: RgbaColor::hex("#524a3e", 0x52, 0x4a, 0x3e),
        text_on_solid: RgbaColor::hex("#ffffff", 0xff, 0xff, 0xff),
        close_hover_bg: RgbaColor::hex("#c42b1c", 0xc4, 0x2b, 0x1c),
        close_active_bg: RgbaColor::hex("#9e2216", 0x9e, 0x22, 0x16),
        backdrop_overlay: RgbaColor::rgba("rgba(31,28,23,0.36)", 31, 28, 23, 0.36),
        shadow_card: ShadowSpec {
            layers: DAYLIGHT_SHADOW_CARD,
            raw: "0 1px 3px rgba(31,28,23,0.06), 0 1px 2px rgba(31,28,23,0.04)",
        },
        shadow_card_hover: ShadowSpec {
            layers: DAYLIGHT_SHADOW_CARD_HOVER,
            raw: "0 4px 12px rgba(31,28,23,0.09)",
        },
        shadow_dialog: ShadowSpec {
            layers: DAYLIGHT_SHADOW_DIALOG,
            raw: "0 20px 44px rgba(31,28,23,0.18)",
        },
        scrollbar_thumb: RgbaColor::hex("#c9bfa9", 0xc9, 0xbf, 0xa9),
        scrollbar_thumb_hover: RgbaColor::hex("#a69a82", 0xa6, 0x9a, 0x82),
        bg_app_glow: None,
        surface_top_highlight: None,
    },
    // 8. frost-slate — Северный лёд
    ThemeDefinition {
        id: ThemeId::FrostSlate,
        id_str: "frost-slate",
        name_ru: "Северный лёд",
        is_dark: false,
        boot_bg: RgbaColor::hex("#e8eef5", 0xe8, 0xee, 0xf5),
        boot_text: RgbaColor::hex("#141e30", 0x14, 0x1e, 0x30),
        preview_bg: RgbaColor::hex("#e8eef5", 0xe8, 0xee, 0xf5),
        preview_surface: RgbaColor::hex("#f5f8fc", 0xf5, 0xf8, 0xfc),
        preview_elevated: RgbaColor::hex("#e1e8f2", 0xe1, 0xe8, 0xf2),
        preview_border: RgbaColor::hex("#cdd8e6", 0xcd, 0xd8, 0xe6),
        preview_accent: RgbaColor::hex("#3749a6", 0x37, 0x49, 0xa6),
        preview_accent_text: RgbaColor::hex("#2c3d91", 0x2c, 0x3d, 0x91),
        preview_text: RgbaColor::hex("#141e30", 0x14, 0x1e, 0x30),
        bg_app: RgbaColor::hex("#e8eef5", 0xe8, 0xee, 0xf5),
        bg_surface: RgbaColor::hex("#f5f8fc", 0xf5, 0xf8, 0xfc),
        bg_elevated: RgbaColor::hex("#e1e8f2", 0xe1, 0xe8, 0xf2),
        bg_hover: RgbaColor::hex("#d4dfed", 0xd4, 0xdf, 0xed),
        bg_active: RgbaColor::hex("#c5d4e6", 0xc5, 0xd4, 0xe6),
        bg_titlebar: RgbaColor::rgba("rgba(232,238,245,0.95)", 232, 238, 245, 0.95),
        border_subtle: RgbaColor::hex("#cdd8e6", 0xcd, 0xd8, 0xe6),
        border_strong: RgbaColor::hex("#aebfd4", 0xae, 0xbf, 0xd4),
        border_input: RgbaColor::hex("#7487a1", 0x74, 0x87, 0xa1),
        text_primary: RgbaColor::hex("#141e30", 0x14, 0x1e, 0x30),
        text_secondary: RgbaColor::hex("#384861", 0x38, 0x48, 0x61),
        text_muted: RgbaColor::hex("#4f6079", 0x4f, 0x60, 0x79),
        accent_solid: RgbaColor::hex("#3749a6", 0x37, 0x49, 0xa6),
        accent_solid_hover: RgbaColor::hex("#2c3b8a", 0x2c, 0x3b, 0x8a),
        accent_solid_active: RgbaColor::hex("#222e70", 0x22, 0x2e, 0x70),
        accent_text: RgbaColor::hex("#2c3d91", 0x2c, 0x3d, 0x91),
        accent_card_tint: RgbaColor::rgba("rgba(55,73,166,0.06)", 55, 73, 166, 0.06),
        accent_soft: RgbaColor::rgba("rgba(55,73,166,0.11)", 55, 73, 166, 0.11),
        accent_border: RgbaColor::rgba("rgba(55,73,166,0.30)", 55, 73, 166, 0.30),
        status_active_text: RgbaColor::hex("#04694b", 0x04, 0x69, 0x4b),
        status_active_soft: RgbaColor::rgba("rgba(5,150,105,0.10)", 5, 150, 105, 0.10),
        status_active_border: RgbaColor::rgba("rgba(5,150,105,0.32)", 5, 150, 105, 0.32),
        status_warn_text: RgbaColor::hex("#874707", 0x87, 0x47, 0x07),
        status_warn_soft: RgbaColor::rgba("rgba(217,119,6,0.11)", 217, 119, 6, 0.11),
        status_warn_border: RgbaColor::rgba("rgba(180,83,9,0.32)", 180, 83, 9, 0.32),
        status_danger_solid: RgbaColor::hex("#c22035", 0xc2, 0x20, 0x35),
        status_danger_solid_hover: RgbaColor::hex("#a1182a", 0xa1, 0x18, 0x2a),
        status_danger_text: RgbaColor::hex("#ad1b2f", 0xad, 0x1b, 0x2f),
        status_danger_soft: RgbaColor::rgba("rgba(220,38,38,0.09)", 220, 38, 38, 0.09),
        status_danger_border: RgbaColor::rgba("rgba(220,38,38,0.30)", 220, 38, 38, 0.30),
        focus_ring: RgbaColor::hex("#3749a6", 0x37, 0x49, 0xa6),
        switch_off_bg: RgbaColor::hex("#ccd6e4", 0xcc, 0xd6, 0xe4),
        switch_off_border: RgbaColor::hex("#7487a1", 0x74, 0x87, 0xa1),
        switch_off_thumb: RgbaColor::hex("#3d4e66", 0x3d, 0x4e, 0x66),
        text_on_solid: RgbaColor::hex("#ffffff", 0xff, 0xff, 0xff),
        close_hover_bg: RgbaColor::hex("#c42b1c", 0xc4, 0x2b, 0x1c),
        close_active_bg: RgbaColor::hex("#9e2216", 0x9e, 0x22, 0x16),
        backdrop_overlay: RgbaColor::rgba("rgba(20,30,48,0.36)", 20, 30, 48, 0.36),
        shadow_card: ShadowSpec {
            layers: FROST_SHADOW_CARD,
            raw: "0 1px 3px rgba(20,30,48,0.06), 0 1px 2px rgba(20,30,48,0.04)",
        },
        shadow_card_hover: ShadowSpec {
            layers: FROST_SHADOW_CARD_HOVER,
            raw: "0 4px 12px rgba(20,30,48,0.10)",
        },
        shadow_dialog: ShadowSpec {
            layers: FROST_SHADOW_DIALOG,
            raw: "0 20px 44px rgba(20,30,48,0.19)",
        },
        scrollbar_thumb: RgbaColor::hex("#b6c5d9", 0xb6, 0xc5, 0xd9),
        scrollbar_thumb_hover: RgbaColor::hex("#8ea2bd", 0x8e, 0xa2, 0xbd),
        bg_app_glow: Some(GlowSpec {
            rx_px: 760.0,
            ry_px: 260.0,
            cx_pct: 20.0,
            cy_pct: 0.0,
            color: RgbaColor::rgba("rgba(55,73,166,0.05)", 55, 73, 166, 0.05),
            stop_pct: 70.0,
            raw: "radial-gradient(760px 260px at 20% 0%, rgba(55,73,166,0.05), transparent 70%)",
        }),
        surface_top_highlight: Some(RgbaColor::rgba(
            "rgba(255,255,255,0.65)",
            255,
            255,
            255,
            0.65,
        )),
    },
];

pub const fn all_themes() -> &'static [ThemeDefinition; 8] {
    &THEMES
}

pub fn get_theme_by_id(id: ThemeId) -> &'static ThemeDefinition {
    match id {
        ThemeId::Dark => &THEMES[0],
        ThemeId::OledObsidian => &THEMES[1],
        ThemeId::EmeraldOps => &THEMES[2],
        ThemeId::GraphiteAmber => &THEMES[3],
        ThemeId::MidnightViolet => &THEMES[4],
        ThemeId::Light => &THEMES[5],
        ThemeId::DaylightWarm => &THEMES[6],
        ThemeId::FrostSlate => &THEMES[7],
    }
}

pub fn get_theme(id: &str) -> &'static ThemeDefinition {
    ThemeId::parse(id)
        .map(get_theme_by_id)
        .unwrap_or(&THEMES[0])
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ThemePreferences {
    pub theme: ThemeId,
    pub last_dark_theme: ThemeId,
    pub last_light_theme: ThemeId,
}

impl Default for ThemePreferences {
    fn default() -> Self {
        Self {
            theme: ThemeId::Dark,
            last_dark_theme: ThemeId::Dark,
            last_light_theme: ThemeId::Light,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
struct RawThemePreferences {
    #[serde(default)]
    theme: Option<String>,
    #[serde(rename = "ugm-last-dark-theme", default)]
    last_dark: Option<String>,
    #[serde(rename = "ugm-last-light-theme", default)]
    last_light: Option<String>,
}

fn is_target_dir_writable(dir: &Path) -> bool {
    let probe = dir.join(format!(
        ".ugm_theme_probe_{}_{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0)
    ));
    match std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&probe)
    {
        Ok(_) => {
            let _ = std::fs::remove_file(&probe);
            true
        }
        Err(_) => false,
    }
}

fn is_primary_writable(primary: &Path) -> bool {
    if let Some(parent) = primary.parent() {
        if parent.exists() {
            return is_target_dir_writable(parent);
        }
        for anc in parent.ancestors().skip(1) {
            if anc.exists() {
                return is_target_dir_writable(anc);
            }
        }
    }
    false
}

fn write_preferences_file(path: &Path, prefs: &ThemePreferences) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| {
            format!(
                "Не удалось создать каталог настроек темы {}: {}",
                parent.display(),
                e
            )
        })?;
    }
    let raw = RawThemePreferences {
        theme: Some(prefs.theme.as_str().to_string()),
        last_dark: Some(prefs.last_dark_theme.as_str().to_string()),
        last_light: Some(prefs.last_light_theme.as_str().to_string()),
    };
    let json = serde_json::to_string_pretty(&raw)
        .map_err(|e| format!("Ошибка сериализации настроек темы: {}", e))?;
    let tmp = path.with_extension(format!("tmp.{}", std::process::id()));
    if std::fs::write(&tmp, json.as_bytes()).is_ok() {
        if std::fs::rename(&tmp, path).is_ok() {
            return Ok(());
        }
        let _ = std::fs::remove_file(&tmp);
    }
    std::fs::write(path, json.as_bytes())
        .map_err(|e| format!("Не удалось записать {}: {}", path.display(), e))
}

pub fn default_fallback_settings_path() -> Option<PathBuf> {
    #[cfg(target_os = "windows")]
    {
        std::env::var_os("LOCALAPPDATA")
            .map(|p| PathBuf::from(p).join("UltraGamingMode").join("ui_settings.json"))
    }
    #[cfg(not(target_os = "windows"))]
    {
        std::env::var_os("XDG_CONFIG_HOME")
            .or_else(|| std::env::var_os("HOME"))
            .map(|p| PathBuf::from(p).join("UltraGamingMode").join("ui_settings.json"))
    }
}

impl ThemePreferences {
    pub fn from_json_str(raw: &str) -> Self {
        let clean = raw.trim_start_matches('\u{feff}');
        let Ok(parsed) = serde_json::from_str::<RawThemePreferences>(clean) else {
            return Self::default();
        };

        let theme = parsed
            .theme
            .as_deref()
            .and_then(ThemeId::parse)
            .unwrap_or(ThemeId::Dark);

        let mut last_dark_theme = parsed
            .last_dark
            .as_deref()
            .and_then(ThemeId::parse)
            .filter(|id| id.is_dark())
            .unwrap_or(ThemeId::Dark);

        let mut last_light_theme = parsed
            .last_light
            .as_deref()
            .and_then(ThemeId::parse)
            .filter(|id| !id.is_dark())
            .unwrap_or(ThemeId::Light);

        if theme.is_dark() {
            let explicit_dark_valid = parsed
                .last_dark
                .as_deref()
                .and_then(ThemeId::parse)
                .map(|id| id.is_dark())
                .unwrap_or(false);
            if !explicit_dark_valid || parsed.last_dark.is_none() {
                last_dark_theme = theme;
            }
        } else {
            let explicit_light_valid = parsed
                .last_light
                .as_deref()
                .and_then(ThemeId::parse)
                .map(|id| !id.is_dark())
                .unwrap_or(false);
            if !explicit_light_valid || parsed.last_light.is_none() {
                last_light_theme = theme;
            }
        }

        Self {
            theme,
            last_dark_theme,
            last_light_theme,
        }
    }

    pub fn load_from_paths(primary: &Path, fallback: Option<&Path>) -> Self {
        let primary_writable = is_primary_writable(primary);
        if primary_writable {
            if let Ok(raw) = std::fs::read_to_string(primary) {
                return Self::from_json_str(&raw);
            }
            if let Some(fb) = fallback {
                if let Ok(raw) = std::fs::read_to_string(fb) {
                    return Self::from_json_str(&raw);
                }
            }
        } else {
            if let Some(fb) = fallback {
                if let Ok(raw) = std::fs::read_to_string(fb) {
                    return Self::from_json_str(&raw);
                }
            }
            if let Ok(raw) = std::fs::read_to_string(primary) {
                return Self::from_json_str(&raw);
            }
        }
        Self::default()
    }

    pub fn save_to_paths(&self, primary: &Path, fallback: Option<&Path>) -> Result<PathBuf, String> {
        if is_primary_writable(primary) {
            if write_preferences_file(primary, self).is_ok() {
                return Ok(primary.to_path_buf());
            }
        }
        if let Some(fb) = fallback {
            write_preferences_file(fb, self)?;
            return Ok(fb.to_path_buf());
        }
        write_preferences_file(primary, self)?;
        Ok(primary.to_path_buf())
    }

    pub fn load_from_runtime(runtime_root: &Path) -> Self {
        let primary = runtime_root.join("Config").join("ui_settings.json");
        let fallback = default_fallback_settings_path();
        Self::load_from_paths(&primary, fallback.as_deref())
    }

    pub fn save_to_runtime(&self, runtime_root: &Path) -> Result<PathBuf, String> {
        let primary = runtime_root.join("Config").join("ui_settings.json");
        let fallback = default_fallback_settings_path();
        self.save_to_paths(&primary, fallback.as_deref())
    }

    pub fn toggle_polarity(&mut self) -> ThemeId {
        if self.theme.is_dark() {
            self.last_dark_theme = self.theme;
            self.theme = self.last_light_theme;
        } else {
            self.last_light_theme = self.theme;
            self.theme = self.last_dark_theme;
        }
        self.theme
    }

    pub fn select_theme(&mut self, id: ThemeId) -> ThemeId {
        self.theme = id;
        if id.is_dark() {
            self.last_dark_theme = id;
        } else {
            self.last_light_theme = id;
        }
        id
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_all_8_themes_order_metadata_and_exact_tokens() {
        let themes = all_themes();
        assert_eq!(themes.len(), 8);

        let expected_meta = [
            ("dark", "Тёмная классика", true, "#0c0f14", "#f1f5f9", "#131720", "#1b202c", "#242b38", "#2563eb", "#74b4fc"),
            ("oled-obsidian", "OLED Обсидиан", true, "#000000", "#f3f6fa", "#090b0f", "#11151d", "#1c222e", "#0275a6", "#4cc4fa"),
            ("emerald-ops", "Тактический изумруд", true, "#090e0d", "#edf6f2", "#101715", "#17221f", "#202e2a", "#0e7478", "#3ddbe0"),
            ("graphite-amber", "Спокойный графит", true, "#141518", "#f3f1ec", "#1b1d21", "#24272d", "#2c3037", "#c2410c", "#fb9b52"),
            ("midnight-violet", "Глубокая ночь", true, "#0d0c16", "#f3f1fc", "#151324", "#1f1c33", "#292542", "#7c3aed", "#c4a8fd"),
            ("light", "Светлая классика", false, "#f3f6fa", "#0f172a", "#ffffff", "#edf2f7", "#dce4ee", "#2563eb", "#1d4ed8"),
            ("daylight-warm", "Тёплая дневная", false, "#f3efe6", "#1f1c17", "#fbf9f4", "#ece6da", "#ddd5c6", "#0b6e73", "#096166"),
            ("frost-slate", "Северный лёд", false, "#e8eef5", "#141e30", "#f5f8fc", "#e1e8f2", "#cdd8e6", "#3749a6", "#2c3d91"),
        ];

        for (idx, (id, name_ru, is_dark, bg, text, surf, elev, border, acc, acc_text)) in
            expected_meta.iter().enumerate()
        {
            let t = &themes[idx];
            assert_eq!(t.id_str, *id);
            assert_eq!(t.id.as_str(), *id);
            assert_eq!(t.name_ru, *name_ru);
            assert_eq!(t.is_dark, *is_dark);
            assert_eq!(t.boot_bg.as_str(), *bg);
            assert_eq!(t.boot_text.as_str(), *text);
            assert_eq!(t.preview_bg.as_str(), *bg);
            assert_eq!(t.preview_surface.as_str(), *surf);
            assert_eq!(t.preview_elevated.as_str(), *elev);
            assert_eq!(t.preview_border.as_str(), *border);
            assert_eq!(t.preview_accent.as_str(), *acc);
            assert_eq!(t.preview_accent_text.as_str(), *acc_text);
            assert_eq!(t.preview_text.as_str(), *text);

            assert_eq!(t.bg_app.as_str(), *bg);
            assert_eq!(t.bg_surface.as_str(), *surf);
            assert_eq!(t.bg_elevated.as_str(), *elev);
            assert_eq!(t.border_subtle.as_str(), *border);
            assert_eq!(t.accent_solid.as_str(), *acc);
            assert_eq!(t.accent_text.as_str(), *acc_text);
            assert_eq!(t.text_primary.as_str(), *text);
            assert_eq!(get_theme(id).id, t.id);
        }

        // Verify optional enhancement tokens exist strictly on themes 3, 4, 5, 8
        assert!(get_theme("dark").bg_app_glow.is_none());
        assert!(get_theme("dark").surface_top_highlight.is_none());
        assert!(get_theme("oled-obsidian").bg_app_glow.is_none());
        assert!(get_theme("oled-obsidian").surface_top_highlight.is_none());
        assert!(get_theme("light").bg_app_glow.is_none());
        assert!(get_theme("light").surface_top_highlight.is_none());
        assert!(get_theme("daylight-warm").bg_app_glow.is_none());
        assert!(get_theme("daylight-warm").surface_top_highlight.is_none());

        let emerald = get_theme("emerald-ops");
        assert_eq!(
            emerald.bg_app_glow.unwrap().raw,
            "radial-gradient(700px 260px at 18% 0%, rgba(20,184,184,0.065), transparent 70%)"
        );
        assert_eq!(
            emerald.surface_top_highlight.unwrap().as_str(),
            "rgba(61,219,224,0.08)"
        );

        let graphite = get_theme("graphite-amber");
        assert_eq!(
            graphite.bg_app_glow.unwrap().raw,
            "radial-gradient(700px 260px at 82% 0%, rgba(249,115,22,0.055), transparent 70%)"
        );
        assert_eq!(
            graphite.surface_top_highlight.unwrap().as_str(),
            "rgba(251,155,82,0.07)"
        );

        let midnight = get_theme("midnight-violet");
        assert_eq!(
            midnight.bg_app_glow.unwrap().raw,
            "radial-gradient(720px 280px at 50% 0%, rgba(139,92,246,0.085), transparent 72%)"
        );
        assert_eq!(
            midnight.surface_top_highlight.unwrap().as_str(),
            "rgba(196,168,253,0.09)"
        );

        let frost = get_theme("frost-slate");
        assert_eq!(
            frost.bg_app_glow.unwrap().raw,
            "radial-gradient(760px 260px at 20% 0%, rgba(55,73,166,0.05), transparent 70%)"
        );
        assert_eq!(
            frost.surface_top_highlight.unwrap().as_str(),
            "rgba(255,255,255,0.65)"
        );

        // Verify oled-obsidian spread shadow and light 2-layer shadows
        let oled = get_theme("oled-obsidian");
        assert_eq!(oled.shadow_card.as_str(), "0 0 0 1px rgba(255,255,255,0.02)");
        assert_eq!(oled.shadow_card.primary().spread, 1.0);
        assert!(oled.shadow_card.secondary().is_none());

        let light = get_theme("light");
        assert_eq!(
            light.shadow_card.as_str(),
            "0 1px 3px rgba(15,23,42,0.06), 0 1px 2px rgba(15,23,42,0.04)"
        );
        assert!(light.shadow_card.secondary().is_some());

        // Unknown theme falls back to Dark
        assert_eq!(get_theme("nonexistent-theme").id, ThemeId::Dark);
    }

    #[test]
    fn test_all_43_base_tokens_exact_strings_per_theme() {
        // Verify key differentiating tokens across all 8 themes against ORIGINAL_REQUEST.md
        let d = get_theme("dark");
        assert_eq!(d.bg_hover.as_str(), "#232a38");
        assert_eq!(d.bg_active.as_str(), "#2c3547");
        assert_eq!(d.bg_titlebar.as_str(), "rgba(12,15,20,0.94)");
        assert_eq!(d.border_strong.as_str(), "#374156");
        assert_eq!(d.border_input.as_str(), "#586884");
        assert_eq!(d.text_secondary.as_str(), "#a3b3c9");
        assert_eq!(d.text_muted.as_str(), "#8293ab");
        assert_eq!(d.accent_solid_hover.as_str(), "#1d4ed8");
        assert_eq!(d.accent_solid_active.as_str(), "#1e40af");
        assert_eq!(d.accent_card_tint.as_str(), "rgba(59,130,246,0.08)");
        assert_eq!(d.accent_soft.as_str(), "rgba(59,130,246,0.15)");
        assert_eq!(d.accent_border.as_str(), "rgba(96,165,250,0.36)");
        assert_eq!(d.status_active_text.as_str(), "#34d399");
        assert_eq!(d.status_warn_text.as_str(), "#fbbf24");
        assert_eq!(d.status_danger_solid.as_str(), "#dc2626");
        assert_eq!(d.focus_ring.as_str(), "#60a5fa");
        assert_eq!(d.switch_off_bg.as_str(), "#252c3b");
        assert_eq!(d.backdrop_overlay.as_str(), "rgba(6,8,12,0.72)");
        assert_eq!(d.scrollbar_thumb.as_str(), "#2e3748");
        assert_eq!(d.scrollbar_thumb_hover.as_str(), "#46536b");

        let dw = get_theme("daylight-warm");
        assert_eq!(dw.bg_hover.as_str(), "#e2dacb");
        assert_eq!(dw.bg_active.as_str(), "#d5cbb8");
        assert_eq!(dw.bg_titlebar.as_str(), "rgba(243,239,230,0.95)");
        assert_eq!(dw.status_active_text.as_str(), "#1b6628");
        assert_eq!(dw.status_warn_text.as_str(), "#8a4706");
        assert_eq!(dw.status_danger_solid.as_str(), "#c2252d");
        assert_eq!(dw.scrollbar_thumb.as_str(), "#c9bfa9");
        assert_eq!(dw.scrollbar_thumb_hover.as_str(), "#a69a82");

        let fs = get_theme("frost-slate");
        assert_eq!(fs.bg_hover.as_str(), "#d4dfed");
        assert_eq!(fs.bg_active.as_str(), "#c5d4e6");
        assert_eq!(fs.bg_titlebar.as_str(), "rgba(232,238,245,0.95)");
        assert_eq!(fs.status_active_text.as_str(), "#04694b");
        assert_eq!(fs.status_warn_text.as_str(), "#874707");
        assert_eq!(fs.status_danger_solid.as_str(), "#c22035");
        assert_eq!(fs.shadow_card_hover.as_str(), "0 4px 12px rgba(20,30,48,0.10)");
        assert_eq!(fs.shadow_dialog.as_str(), "0 20px 44px rgba(20,30,48,0.19)");
        assert_eq!(fs.scrollbar_thumb.as_str(), "#b6c5d9");
        assert_eq!(fs.scrollbar_thumb_hover.as_str(), "#8ea2bd");
    }

    #[test]
    fn test_theme_preferences_persistence_smart_toggle_and_legacy_fallback() {
        // Legacy "light" JSON without ugm-last-*-theme keys and with UTF-8 BOM
        let legacy_light = ThemePreferences::from_json_str("\u{feff}{\"theme\":\"light\"}");
        assert_eq!(legacy_light.theme, ThemeId::Light);
        assert_eq!(legacy_light.last_dark_theme, ThemeId::Dark);
        assert_eq!(legacy_light.last_light_theme, ThemeId::Light);

        // Cross-polarity validation: light ID inside ugm-last-dark-theme is rejected -> Dark
        let invalid_polarity = ThemePreferences::from_json_str(
            r#"{"theme":"emerald-ops","ugm-last-dark-theme":"frost-slate","ugm-last-light-theme":"oled-obsidian"}"#,
        );
        assert_eq!(invalid_polarity.theme, ThemeId::EmeraldOps);
        assert_eq!(invalid_polarity.last_dark_theme, ThemeId::EmeraldOps);
        assert_eq!(invalid_polarity.last_light_theme, ThemeId::Light);

        // Unknown / corrupt JSON falls back cleanly
        let corrupt = ThemePreferences::from_json_str("{not-json");
        assert_eq!(corrupt, ThemePreferences::default());

        // Smart toggle remembers last dark & last light themes
        let mut prefs = ThemePreferences::default();
        prefs.select_theme(ThemeId::MidnightViolet);
        assert_eq!(prefs.last_dark_theme, ThemeId::MidnightViolet);
        assert_eq!(prefs.toggle_polarity(), ThemeId::Light);
        prefs.select_theme(ThemeId::FrostSlate);
        assert_eq!(prefs.last_light_theme, ThemeId::FrostSlate);
        assert_eq!(prefs.toggle_polarity(), ThemeId::MidnightViolet);
        assert_eq!(prefs.toggle_polarity(), ThemeId::FrostSlate);

        // Roundtrip persistence without UTF-8 BOM
        let temp_dir =
            std::env::temp_dir().join(format!("ugm_theme_prefs_test_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&temp_dir);
        let primary = temp_dir.join("Config").join("ui_settings.json");
        let fallback = temp_dir.join("LocalAppData").join("ui_settings.json");

        let saved_path = prefs
            .save_to_paths(&primary, Some(&fallback))
            .expect("save_to_paths should succeed");
        assert_eq!(saved_path, primary);
        let raw_bytes = std::fs::read(&primary).expect("read ui_settings.json");
        assert!(!raw_bytes.starts_with(&[0xEF, 0xBB, 0xBF]));

        let reloaded = ThemePreferences::load_from_paths(&primary, Some(&fallback));
        assert_eq!(reloaded, prefs);

        let _ = std::fs::remove_dir_all(&temp_dir);
    }
}
