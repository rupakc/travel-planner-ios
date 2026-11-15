import VoyagerModel

/// The one gate for registering this device for server push (R16): the server has an Apple key (`features.apns`) and the
/// person allowed notifications. Nothing in this task registers a device; the APNs registration (T48, which needs the
/// owner's Apple account) asks this first, so nothing is sent to a server that cannot use it or to a phone that said no.
public enum PushGate {
    public static func shouldRegister(config: ClientConfig?, permission: NotificationPermissionState) -> Bool {
        shouldRegister(features: RemoteFeatures(config: config), permission: permission)
    }

    public static func shouldRegister(features: RemoteFeatures, permission: NotificationPermissionState) -> Bool {
        features.apns && permission == .allowed
    }
}
