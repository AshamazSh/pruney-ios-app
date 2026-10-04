import SwiftUI
import UIKit

// Native touch events keep short taps independent of long-press recognition.
struct UndoHoldButton: UIViewRepresentable {
    let enabled: Bool
    let onPressChanged: (Bool) -> Void
    let onTap: () -> Void
    let onHold: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "arrow.uturn.backward", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)), for: .normal)
        button.tintColor = .secondaryLabel
        button.accessibilityLabel = "Undo last decision"
        button.accessibilityHint = "Hold for 1.5 seconds to reset all selections"
        button.accessibilityIdentifier = "review.undo"
        button.addTarget(context.coordinator, action: #selector(Coordinator.pressed), for: .touchDown)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        button.addTarget(context.coordinator, action: #selector(Coordinator.cancelled), for: [.touchUpOutside, .touchCancel, .touchDragExit])
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.held(_:)))
        hold.minimumPressDuration = 1.5
        hold.allowableMovement = 20
        // A recognized hold cancels the button's tap; a failed hold leaves the tap intact.
        hold.cancelsTouchesInView = true
        hold.delaysTouchesBegan = false
        hold.delaysTouchesEnded = false
        button.addGestureRecognizer(hold)
        button.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Reset all selections", target: context.coordinator, selector: #selector(Coordinator.accessibilityReset))
        ]
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.parent = self
        button.isEnabled = enabled
    }

    final class Coordinator: NSObject {
        var parent: UndoHoldButton
        private var recognizedHold = false

        init(_ parent: UndoHoldButton) { self.parent = parent }

        @objc func pressed() {
            guard parent.enabled else { return }
            recognizedHold = false
            parent.onPressChanged(true)
        }

        @objc func tapped() {
            parent.onPressChanged(false)
            guard parent.enabled, !recognizedHold else { return }
            parent.onTap()
        }

        @objc func cancelled() { parent.onPressChanged(false) }

        @objc func held(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began:
                guard parent.enabled else { return }
                recognizedHold = true
                parent.onPressChanged(false)
                parent.onHold()
            case .ended, .cancelled, .failed:
                parent.onPressChanged(false)
                recognizedHold = false
            default: break
            }
        }

        @objc func accessibilityReset() -> Bool {
            guard parent.enabled else { return false }
            parent.onHold()
            return true
        }
    }
}
