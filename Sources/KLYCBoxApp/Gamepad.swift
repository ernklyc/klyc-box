import GameController
import Observation

/// A game controller as the way to move around the app: D-pad along the shelf, A to play, bumpers between sections.
/// Events are plain values in an observable, so any screen can react with `.onChange(of: pad.event?.id)`.
@Observable @MainActor
final class Gamepad {
    enum Button { case left, right, up, down, accept, back, previousSection, nextSection }
    struct Event: Equatable { let id = UUID(); let button: Button }

    static let shared = Gamepad()
    var event: Event?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            guard let controller = note.object as? GCController else { return }
            Task { @MainActor in self?.attach(controller) }
        }
        for controller in GCController.controllers() { attach(controller) }
    }

    private func attach(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        func bind(_ input: GCControllerButtonInput, _ button: Button) {
            input.pressedChangedHandler = { [weak self] _, _, pressed in
                guard pressed else { return }
                Task { @MainActor in self?.event = Event(button: button) }
            }
        }
        bind(pad.dpad.left, .left); bind(pad.dpad.right, .right); bind(pad.dpad.up, .up); bind(pad.dpad.down, .down)
        bind(pad.buttonA, .accept); bind(pad.buttonB, .back)
        bind(pad.leftShoulder, .previousSection); bind(pad.rightShoulder, .nextSection)
    }
}
