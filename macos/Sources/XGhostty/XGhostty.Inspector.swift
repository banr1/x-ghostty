import XGhosttyKit
import Metal

extension XGhostty {
    /// Represents the inspector for a surface within XGhostty.
    ///
    /// Wraps a `xghostty_inspector_t`
    final class Inspector: Sendable {
        private let inspector: xghostty_inspector_t

        /// Read the underlying C value for this inspector. This is unsafe because the value will be
        /// freed when the Inspector class is deinitialized.
        var unsafeCValue: xghostty_inspector_t {
            inspector
        }

        /// Initialize from the C structure.
        init(cInspector: xghostty_inspector_t) {
            self.inspector = cInspector
        }

        /// Set the focus state of the inspector.
        @MainActor
        func setFocus(_ focused: Bool) {
            xghostty_inspector_set_focus(inspector, focused)
        }

        /// Set the content scale of the inspector.
        @MainActor
        func setContentScale(x: Double, y: Double) {
            xghostty_inspector_set_content_scale(inspector, x, y)
        }

        /// Set the size of the inspector.
        @MainActor
        func setSize(width: UInt32, height: UInt32) {
            xghostty_inspector_set_size(inspector, width, height)
        }

        /// Send a mouse button event to the inspector.
        @MainActor
        func mouseButton(
            _ state: xghostty_input_mouse_state_e,
            button: xghostty_input_mouse_button_e,
            mods: xghostty_input_mods_e
        ) {
            xghostty_inspector_mouse_button(inspector, state, button, mods)
        }

        /// Send a mouse position event to the inspector.
        @MainActor
        func mousePos(x: Double, y: Double) {
            xghostty_inspector_mouse_pos(inspector, x, y)
        }

        /// Send a mouse scroll event to the inspector.
        @MainActor
        func mouseScroll(x: Double, y: Double, mods: xghostty_input_scroll_mods_t) {
            xghostty_inspector_mouse_scroll(inspector, x, y, mods)
        }

        /// Send a key event to the inspector.
        @MainActor
        func key(
            _ action: xghostty_input_action_e,
            key: xghostty_input_key_e,
            mods: xghostty_input_mods_e
        ) {
            xghostty_inspector_key(inspector, action, key, mods)
        }

        /// Send text to the inspector.
        @MainActor
        func text(_ text: String) {
            text.withCString { ptr in
                xghostty_inspector_text(inspector, ptr)
            }
        }

        /// Initialize Metal rendering for the inspector.
        @MainActor
        func metalInit(device: MTLDevice) -> Bool {
            let devicePtr = Unmanaged.passRetained(device).toOpaque()
            return xghostty_inspector_metal_init(inspector, devicePtr)
        }

        /// Render the inspector using Metal.
        @MainActor
        func metalRender(
            commandBuffer: MTLCommandBuffer,
            descriptor: MTLRenderPassDescriptor
        ) {
            xghostty_inspector_metal_render(
                inspector,
                Unmanaged.passRetained(commandBuffer).toOpaque(),
                Unmanaged.passRetained(descriptor).toOpaque()
            )
        }
    }
}
