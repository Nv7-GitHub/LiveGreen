import Foundation
import Network
import Observation
import os
import GreenCore

/// Browses the local network for Shelly plugs (`_shelly._tcp`) and resolves them to host/port.
@Observable
final class BonjourBrowser {
    struct Service: Identifiable, Hashable {
        var name: String
        var endpoint: NWEndpoint
        var id: String { name }
    }

    enum State: Equatable {
        case idle, searching
        case failed(String)
    }

    private(set) var services: [Service] = []
    private(set) var state: State = .idle

    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored let serviceType: String

    init(serviceType: String = "_shelly._tcp") {
        self.serviceType = serviceType
    }

    func start() {
        stop()
        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: .tcp)
        browser.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in self?.handle(newState) }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.compactMap { result -> Service? in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                return Service(name: name, endpoint: result.endpoint)
            }
            Task { @MainActor in self?.services = found.sorted { $0.name < $1.name } }
        }
        browser.start(queue: .main)
        self.browser = browser
        state = .searching
    }

    func stop() {
        browser?.cancel()
        browser = nil
        if state == .searching { state = .idle }
    }

    private func handle(_ newState: NWBrowser.State) {
        switch newState {
        case .failed(let error), .waiting(let error):
            state = .failed(error.localizedDescription)
        case .cancelled:
            state = .idle
        default:
            break
        }
    }

    /// Resolves a discovered service to an IPv4 host and port by opening a short TCP connection.
    /// Falls back to the mDNS hostname `<name>.local` if resolution doesn't finish in time.
    nonisolated static func resolve(_ service: Service, timeout: Duration = .seconds(4)) async -> PlugEndpoint {
        let fallback = PlugEndpoint(host: "\(service.name).local", port: 80, serviceName: service.name)
        let parameters = NWParameters.tcp
        (parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4
        let connection = NWConnection(to: service.endpoint, using: parameters)
        let finished = OSAllocatedUnfairLock(initialState: false)

        let resolved = await withCheckedContinuation { (continuation: CheckedContinuation<PlugEndpoint, Never>) in
            let finish: @Sendable (PlugEndpoint) -> Void = { endpoint in
                let first = finished.withLock { done in
                    defer { done = true }
                    return !done
                }
                guard first else { return }
                connection.cancel()
                continuation.resume(returning: endpoint)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case .hostPort(let host, let port) = connection.currentPath?.remoteEndpoint {
                        let address = "\(host)".split(separator: "%").first.map(String.init) ?? "\(host)"
                        finish(PlugEndpoint(host: address, port: Int(port.rawValue), serviceName: service.name))
                    } else {
                        finish(fallback)
                    }
                case .failed, .cancelled:
                    finish(fallback)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
            Task {
                try? await Task.sleep(for: timeout)
                finish(fallback)
            }
        }
        return resolved
    }
}
