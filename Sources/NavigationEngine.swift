import Foundation
import CoreLocation
import MapKit
import Combine

/// 核心导航引擎：后台定位 + 沿路线推进 + 距离阈值触发通知
final class NavigationEngine: NSObject, CLLocationManagerDelegate {

    static let shared = NavigationEngine()

    @Published private(set) var state: NavigationState = .idle
    @Published private(set) var currentRoute: RouteInfo?
    @Published private(set) var lastLocation: CLLocation?

    private let locationManager = CLLocationManager()
    private var currentManeuverIndex = 0
    private var announcedThresholds: Set<Int> = []   // 当前 maneuver 已播报的阈值
    private var lastOffRouteCheck = Date.distantPast
    private var lastReplanAt = Date.distantPast

    /// 触发通知的距离阈值（米）。到点前依次播报 500/200/50 米
    private let alertDistances: [Int] = [500, 200, 50]
    /// 偏航判定阈值（米）：离路线折线超过此距离触发重新规划
    private let offRouteThreshold: CLLocationDistance = 80

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.activityType = .fitness   // 骑行/步行更省电且不被暂停
        locationManager.requestAlwaysAuthorization()

        // 关键：声明后台音频，配合静音音频保持 App 在后台长期存活
        configureAudioSession()
    }

    private func configureAudioSession() {
        // 由 AppDelegate 中的 SilentAudioPlayer 负责，这里仅占位说明
    }

    // MARK: - 对外接口

    func start(destination: MKMapItem) {
        state = .locating
        NotificationBridge.shared.requestAuthorization { granted in
            if !granted {
                DispatchQueue.main.async {
                    self.state = .error("通知权限未开启，请在设置中允许")
                }
                return
            }
            self.planRoute(to: destination)
        }
    }

    func stop() {
        locationManager.stopUpdatingLocation()
        currentRoute = nil
        currentManeuverIndex = 0
        announcedThresholds.removeAll()
        NotificationBridge.shared.clear()
        state = .idle
    }

    private func planRoute(to destination: MKMapItem) {
        state = .planning
        let destCoord = destination.placemark.coordinate
        let destName = destination.name ?? "目的地"

        let origin: CLLocationCoordinate2D
        if let loc = locationManager.location {
            origin = loc.coordinate
        } else {
            // 还没定位到，先开始更新，等拿到位置再规划
            locationManager.startUpdatingLocation()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self = self else { return }
                if let loc = self.locationManager.location {
                    self.doPlan(from: loc.coordinate, to: destCoord, name: destName)
                } else {
                    self.state = .error("定位失败，请到户外或检查定位权限")
                }
            }
            return
        }
        doPlan(from: origin, to: destCoord, name: destName)
    }

    private func doPlan(from origin: CLLocationCoordinate2D,
                        to dest: CLLocationCoordinate2D,
                        name: String) {
        RoutePlanner.shared.plan(from: origin, to: dest, destinationName: name) { result in
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    self.state = .error("路线规划失败: \(error.localizedDescription)")
                case .success(let routeInfo):
                    self.currentRoute = routeInfo
                    self.currentManeuverIndex = 0
                    self.announcedThresholds.removeAll()
                    self.locationManager.startUpdatingLocation()
                    self.state = .navigating(
                        remaining: routeInfo.totalDistance,
                        nextManeuver: routeInfo.maneuvers.first?.watchText ?? "直行"
                    )
                    // 起播提示
                    if let first = routeInfo.maneuvers.first {
                        NotificationBridge.shared.postTurn(
                            text: first.watchText,
                            distance: first.cumulativeDistance,
                            force: true
                        )
                    }
                }
            }
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastLocation = location

        guard let route = currentRoute else { return }

        // 到达判定：距终点 < 30 米
        let toDestination = location.distance(from: CLLocation(
            latitude: route.destination.latitude,
            longitude: route.destination.longitude
        ))
        if toDestination < 30 {
            NotificationBridge.shared.postArrival(name: route.destinationName)
            state = .arrived
            stop()
            return
        }

        // 推进 maneuver 指针
        advanceManeuvers(using: location, route: route)

        // 偏航检测（限频：每 15 秒最多一次）
        if Date().timeIntervalSince(lastOffRouteCheck) > 15 {
            lastOffRouteCheck = Date()
            checkOffRoute(using: location, route: route)
        }
    }

    func locationManager(_ manager: CLLocationManager,
                         didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .denied, .restricted:
            state = .error("定位权限被拒绝，请在设置中开启「始终」")
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        state = .error("定位错误: \(error.localizedDescription)")
    }

    // MARK: - 核心算法

    /// 沿路线投影当前位置，找到"下一个尚未通过的 maneuver"，计算剩余距离
    private func advanceManeuvers(using location: CLLocation, route: RouteInfo) {
        let polyline = route.route.polyline
        let projected = polyline.closestPoint(to: location.coordinate)
        let distanceFromStart = approximateDistance(on: polyline, to: projected)

        // 跳过已经通过的 maneuver（累计距离已落后于当前投影点 15 米以上）
        while currentManeuverIndex < route.maneuvers.count &&
                route.maneuvers[currentManeuverIndex].cumulativeDistance < distanceFromStart - 15 {
            currentManeuverIndex += 1
            announcedThresholds.removeAll()
        }

        guard currentManeuverIndex < route.maneuvers.count else {
            // 所有 maneuver 都已过，只剩到达提示
            state = .navigating(remaining: toDestinationDistance(location, route), nextManeuver: "直行到达")
            return
        }

        let maneuver = route.maneuvers[currentManeuverIndex]
        let remaining = max(0, maneuver.cumulativeDistance - distanceFromStart)

        state = .navigating(remaining: remaining, nextManeuver: maneuver.watchText)

        // 阈值播报：500 / 200 / 50 米各一次
        for threshold in alertDistances.sorted(by: >) {
            if remaining <= Double(threshold) && !announcedThresholds.contains(threshold) {
                announcedThresholds.insert(threshold)
                NotificationBridge.shared.postTurn(
                    text: maneuver.watchText,
                    distance: remaining,
                    force: threshold == 50
                )
                break   // 一次位置更新只播报一个阈值
            }
        }
    }

    private func toDestinationDistance(_ location: CLLocation, _ route: RouteInfo) -> CLLocationDistance {
        location.distance(from: CLLocation(latitude: route.destination.latitude,
                                            longitude: route.destination.longitude))
    }

    /// 偏航检测：当前位置到路线折线的最近距离
    private func checkOffRoute(using location: CLLocation, route: RouteInfo) {
        let closest = route.route.polyline.closestPoint(to: location.coordinate)
        let offDistance = location.distance(from: CLLocation(latitude: closest.latitude,
                                                              longitude: closest.longitude))
        guard offDistance > offRouteThreshold else { return }
        // 限频：60 秒内不重复重规划
        guard Date().timeIntervalSince(lastReplanAt) > 60 else { return }
        lastReplanAt = Date()

        // 一次性网络回调，直接强捕获 self（无循环引用风险），
        // 避免 Swift 6 嵌套闭包中 weak self 被擦除为 NSObject 的问题
        RoutePlanner.shared.replan(from: location.coordinate, to: route) { result in
            DispatchQueue.main.async {
                if case .success(let newRoute) = result {
                    self.currentRoute = newRoute
                    self.currentManeuverIndex = 0
                    self.announcedThresholds.removeAll()
                    NotificationBridge.shared.postTurn(text: "已重新规划路线", distance: 0, force: true)
                }
            }
        }
    }

    /// 计算投影点沿折线到起点的近似累计距离
    private func approximateDistance(on polyline: MKPolyline, to point: CLLocationCoordinate2D) -> CLLocationDistance {
        let count = polyline.pointCount
        guard count >= 2 else { return 0 }
        let points = polyline.points()
        var total: CLLocationDistance = 0
        var best: CLLocationDistance = .greatestFiniteMagnitude
        var bestAccumulated: CLLocationDistance = 0

        for i in 0..<(count - 1) {
            let a = points[i].coordinate
            let b = points[i + 1].coordinate
            let seg = CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            let target = CLLocation(latitude: point.latitude, longitude: point.longitude)

            // 简化：用线段中点到投影点的距离近似
            let mid = CLLocationCoordinate2D(latitude: (a.latitude + b.latitude) / 2,
                                              longitude: (a.longitude + b.longitude) / 2)
            let d = target.distance(from: CLLocation(latitude: mid.latitude, longitude: mid.longitude))
            if d < best {
                best = d
                bestAccumulated = total + seg / 2
            }
            total += seg
        }
        return bestAccumulated
    }
}

// MARK: - MKPolyline 投影辅助

extension MKPolyline {
    /// 找到折线上距给定坐标最近的点（线性扫描，路线点数通常 < 2000，性能可接受）
    func closestPoint(to coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let count = self.pointCount
        guard count > 0 else { return coordinate }
        let pts = self.points()

        var best = pts[0].coordinate
        var bestDistance = target.distance(from: CLLocation(latitude: best.latitude, longitude: best.longitude))

        // 每 2 个点采样一次以平衡精度与性能
        var i = 0
        while i < count {
            let c = pts[i].coordinate
            let d = target.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
            if d < bestDistance {
                bestDistance = d
                best = c
            }
            i += 2
        }
        return best
    }
}
