import CoreLocation
import Foundation

/// Where the user allows the app to read their location.
public enum LocationAccess: Sendable, Equatable {
    case notDetermined
    case denied
    case allowed
}

/// Why a position could not be read.
public enum LocationFailure: Error, Sendable, Equatable {
    case denied
    case unavailable
    case timeout
}

public struct Coordinate: Sendable, Equatable {
    public var lat: Double
    public var lng: Double

    public init(lat: Double, lng: Double) {
        self.lat = lat
        self.lng = lng
    }
}

/// The seam over Core Location, so tests never touch the real location services.
@MainActor
public protocol LocationProviding: AnyObject {
    var access: LocationAccess { get }
    /// Shows the system prompt when the choice is still open; returns the resulting access.
    func requestAccess() async -> LocationAccess
    /// One coarse reading (throws `LocationFailure`).
    func currentCoordinate() async throws -> Coordinate
}

/// When-in-use location only, coarse first (`kCLLocationAccuracyKilometer`), one reading per request.
@MainActor
public final class CoreLocationProvider: NSObject, LocationProviding, @preconcurrency CLLocationManagerDelegate {
    private lazy var manager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        return manager
    }()
    private var accessWaiter: CheckedContinuation<LocationAccess, Never>?
    private var fixWaiter: CheckedContinuation<Coordinate, any Error>?
    private var timeoutTask: Task<Void, Never>?
    private let timeout: Duration

    public init(timeout: Duration = .seconds(15)) {
        self.timeout = timeout
        super.init()
    }

    public var access: LocationAccess {
        switch manager.authorizationStatus {
        case .notDetermined: .notDetermined
        case .restricted, .denied: .denied
        case .authorizedAlways, .authorizedWhenInUse: .allowed
        @unknown default: .denied
        }
    }

    public func requestAccess() async -> LocationAccess {
        let current = access
        guard current == .notDetermined, accessWaiter == nil else { return current }
        return await withCheckedContinuation { continuation in
            accessWaiter = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    public func currentCoordinate() async throws -> Coordinate {
        guard access == .allowed else { throw LocationFailure.denied }
        guard fixWaiter == nil else { throw LocationFailure.unavailable }
        return try await withCheckedThrowingContinuation { continuation in
            fixWaiter = continuation
            let limit = timeout
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: limit)
                guard !Task.isCancelled else { return }
                self?.finishFix(.failure(LocationFailure.timeout))
            }
            manager.requestLocation()
        }
    }

    private func finishFix(_ result: Result<Coordinate, any Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        guard let waiter = fixWaiter else { return }
        fixWaiter = nil
        waiter.resume(with: result)
    }

    // MARK: CLLocationManagerDelegate

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let waiter = accessWaiter, access != .notDetermined else { return }
        accessWaiter = nil
        waiter.resume(returning: access)
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        finishFix(.success(Coordinate(lat: last.coordinate.latitude, lng: last.coordinate.longitude)))
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let denied = (error as? CLError)?.code == .denied
        finishFix(.failure(denied ? LocationFailure.denied : LocationFailure.unavailable))
    }
}
