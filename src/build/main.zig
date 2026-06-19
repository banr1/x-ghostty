//! Build logic for XGhostty. A single "build.zig" file became far too complex
//! and spaghetti, so this package extracts the build logic into smaller,
//! more manageable pieces.

pub const gtk = @import("gtk.zig");
pub const Config = @import("Config.zig");
pub const GitVersion = @import("GitVersion.zig");

// Artifacts
pub const XGhosttyBench = @import("XGhosttyBench.zig");
pub const XGhosttyDist = @import("XGhosttyDist.zig");
pub const XGhosttyDocs = @import("XGhosttyDocs.zig");
pub const XGhosttyExe = @import("XGhosttyExe.zig");
pub const XGhosttyFrameData = @import("XGhosttyFrameData.zig");
pub const XGhosttyLib = @import("XGhosttyLib.zig");
pub const XGhosttyLibVt = @import("XGhosttyLibVt.zig");
pub const XGhosttyResources = @import("XGhosttyResources.zig");
pub const XGhosttyI18n = @import("XGhosttyI18n.zig");
pub const XGhosttyXcodebuild = @import("XGhosttyXcodebuild.zig");
pub const XGhosttyXCFramework = @import("XGhosttyXCFramework.zig");
pub const XGhosttyWebdata = @import("XGhosttyWebdata.zig");
pub const XGhosttyZig = @import("XGhosttyZig.zig");
pub const HelpStrings = @import("HelpStrings.zig");
pub const SharedDeps = @import("SharedDeps.zig");
pub const UnicodeTables = @import("UnicodeTables.zig");

// Steps
pub const LibtoolStep = @import("LibtoolStep.zig");
pub const LipoStep = @import("LipoStep.zig");
pub const MetallibStep = @import("MetallibStep.zig");
pub const XCFrameworkStep = @import("XCFrameworkStep.zig");

// Helpers
pub const requireZig = @import("zig.zig").requireZig;
