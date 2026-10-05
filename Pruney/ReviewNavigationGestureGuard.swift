import SwiftUI
import UIKit

/// Disables navigation back gestures only while the review screen is visible.
struct ReviewNavigationGestureGuard: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> GestureGuardController {
        GestureGuardController()
    }

    func updateUIViewController(_ controller: GestureGuardController, context: Context) {
        controller.disableBackGesturesIfVisible()
    }

    static func dismantleUIViewController(_ controller: GestureGuardController, coordinator: ()) {
        controller.restoreBackGestures()
    }

    final class GestureGuardController: UIViewController {
        private var isVisible = false
        private var savedGestures: [(recognizer: UIGestureRecognizer, wasEnabled: Bool)] = []

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            isVisible = true
            disableBackGesturesIfVisible()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            disableBackGesturesIfVisible()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            isVisible = false
            restoreBackGestures()
        }

        func disableBackGesturesIfVisible() {
            guard isVisible, let navigationController else { return }
            var gestures = [navigationController.interactivePopGestureRecognizer].compactMap { $0 }
            if #available(iOS 26.0, *), let contentGesture = navigationController.interactiveContentPopGestureRecognizer {
                gestures.append(contentGesture)
            }
            for gesture in gestures {
                if !savedGestures.contains(where: { $0.recognizer === gesture }) {
                    savedGestures.append((gesture, gesture.isEnabled))
                }
                gesture.isEnabled = false
            }
        }

        func restoreBackGestures() {
            for saved in savedGestures {
                saved.recognizer.isEnabled = saved.wasEnabled
            }
            savedGestures.removeAll()
        }
    }
}
