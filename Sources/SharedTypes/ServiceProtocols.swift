import Foundation

public protocol WorkspaceStore: Sendable {
    var stateDirectoryURL: URL { get }
    var logDirectoryURL: URL { get }

    func loadState() async throws -> PersistedWorkspaceState
    func saveState(_ state: PersistedWorkspaceState) async throws
}

public protocol WindowRegistryService: Sendable {
    func snapshot() async throws -> WindowRegistrySnapshot
    func focusedWindowCandidate() async throws -> WindowCandidate?
}

public protocol WindowControlling: Sendable {
    func setWindowFrame(processID: Int, windowID: Int?, to frame: RectValue) async throws
    func setWindowMinimized(processID: Int, windowID: Int?, to minimized: Bool) async throws
    func setApplicationHidden(processID: Int, to hidden: Bool) async throws
    func activateApplication(processID: Int) async throws
    func raiseWindow(processID: Int, windowID: Int?) async throws
    func focusWindow(processID: Int, windowID: Int?) async throws
}

public protocol LayoutComputing {
    func planLayout(for workspace: Workspace, in geometry: StageGeometry) -> LayoutPlan
}

public protocol VisibilityCoordinating {
    func transition(
        from previousWorkspace: Workspace?,
        to nextWorkspace: Workspace,
        layout: LayoutPlan,
        windows: [WindowCandidate]
    ) async throws -> [VisibilityAction]

    func panicRevealAll() async throws
}

public protocol FocusCoordinating {
    func focus(slotID: String, candidate: WindowCandidate?) async throws
}

public protocol NexusAdapter: AnyObject, Sendable {
    var id: String { get }
    var supportedBundleIDs: [String] { get }

    func discover(in snapshot: WindowRegistrySnapshot) async -> [WindowCandidate]
    func activate(slot: Slot) async throws
    func stage(slot: Slot, action: VisibilityAction) async throws
    func park(slot: Slot) async throws
    func captureState(for slot: Slot) async throws -> AdapterState?
    func restoreState(for slot: Slot, state: AdapterState?) async throws -> RuntimeBinding?
    func openTarget(for slot: Slot) async throws
    func healthCheck() async -> AdapterHealthReport
    func serializeState(_ state: AdapterState) throws -> Data
}

public enum NexusError: LocalizedError {
    case notFound(String)
    case invalidState(String)
    case unsupported(String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let message),
             .invalidState(let message),
             .unsupported(let message),
             .network(let message):
            return message
        }
    }
}
