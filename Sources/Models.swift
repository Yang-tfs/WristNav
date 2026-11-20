import Foundation
import CoreLocation
import MapKit

// MARK: - 转向类型

enum ManeuverKind: String {
    case turnLeft = "左转"
    case turnRight = "右转"
    case slightLeft = "稍向左"
    case slightRight = "稍向右"
    case uturn = "掉头"
    case straight = "直行"
    case roundabout = "环岛"
    case exit = "驶出"
    case arrive = "到达目的地"
    case unknown = "继续前行"

    /// 腕上显示的箭头符号（纯文本，ANCS 可透传）
    var arrow: String {
        switch self {
        case .turnLeft, .slightLeft: return "↰"
        case .turnRight, .slightRight: return "↱"
        case .uturn: return "⤺"
        case .straight: return "↑"
        case .roundabout: return "↻"
        case .exit: return "↪"
        case .arrive: return "◆"
        default: return "→"
        }
    }

    /// 从 MapKit 返回的 instructions 文本解析转向类型
    /// MapKit 在中国区返回中文指令（如"右转进入建国路"），英文区返回 "Turn right onto ..."
    static func from(instruction: String) -> ManeuverKind {
        let s = instruction.lowercased()
        if s.contains("到达") || s.contains("arrive") || s.contains("destination") { return .arrive }
        if s.contains("掉头") || s.contains("uturn") || s.contains("u-turn") { return .uturn }
        if s.contains("环岛") || s.contains("roundabout") || s.contains("rotary") { return .roundabout }
        if s.contains("急左") || s.contains("sharp left") { return .turnLeft }
        if s.contains("急右") || s.contains("sharp right") { return .turnRight }
        if s.contains("稍向左") || s.contains("slight left") || s.contains("bear left") { return .slightLeft }
        if s.contains("稍向右") || s.contains("slight right") || s.contains("bear right") { return .slightRight }
        if s.contains("左转") || s.contains("向左") || s.contains("turn left") { return .turnLeft }
        if s.contains("右转") || s.contains("向右") || s.contains("turn right") { return .turnRight }
        if s.contains("驶出") || s.contains("exit") || s.contains("出口") { return .exit }
        if s.contains("直行") || s.contains("继续") || s.contains("continue") || s.contains("head") { return .straight }
        return .unknown
    }

    /// 是否值得作为独立转向点推送（过滤掉冗长的"继续行驶"）
    var isNotable: Bool {
        switch self {
        case .straight, .unknown: return false
        default: return true
        }
    }
}

// MARK: - 一个转向点

struct Maneuver: Identifiable {
    let id = UUID()
    let kind: ManeuverKind
    let roadName: String
    let instruction: String
    let coordinate: CLLocationCoordinate2D
    /// 从起点到该转向点的累计距离（米）
    let cumulativeDistance: CLLocationDistance
    /// 该 maneuver 所属 step 的序号
    let stepIndex: Int

    /// 腕上通知正文，控制在 40 字符内（ANCS message 字段有限制）
    var watchText: String {
        let road = roadName.isEmpty ? "" : " · \(roadName)"
        return "\(kind.arrow) \(kind.rawValue)\(road)"
    }
}

// MARK: - 路线

struct RouteInfo {
    let route: MKRoute
    let maneuvers: [Maneuver]
    let destination: CLLocationCoordinate2D
    let destinationName: String
    let totalDistance: CLLocationDistance
    let expectedTime: TimeInterval

    init(route: MKRoute, destination: CLLocationCoordinate2D, destinationName: String) {
        self.route = route
        self.destination = destination
        self.destinationName = destinationName
        self.totalDistance = route.distance
        self.expectedTime = route.expectedTravelTime

        var result: [Maneuver] = []
        var accumulated: CLLocationDistance = 0

        for (index, step) in route.steps.enumerated() {
            accumulated += step.distance
            let kind = ManeuverKind.from(instruction: step.instructions)
            // 保留第一个直行段作为起始参考，其余过滤掉无实际转向意义的点
            guard kind.isNotable || index == 0 else { continue }

            let road = Self.extractRoadName(from: step.instructions)
            // 用 step 折线起点作为转向发生位置，比折线中心更准确
            let pts = step.polyline.points()
            let turnCoord = step.polyline.pointCount > 0
                ? pts[0].coordinate
                : step.polyline.coordinate

            result.append(Maneuver(
                kind: kind,
                roadName: road,
                instruction: step.instructions,
                coordinate: turnCoord,
                cumulativeDistance: accumulated,
                stepIndex: index
            ))
        }
        self.maneuvers = result
    }

    /// 从 instructions 中提取路名（兼容中文与英文格式）
    private static func extractRoadName(from instruction: String) -> String {
        let patterns = ["进入", "沿", "驶入", "onto ", "on ", "toward "]
        for pattern in patterns {
            if let range = instruction.range(of: pattern) {
                let tail = String(instruction[range.upperBound...])
                let cleaned = tail
                    .replacingOccurrences(of: "。", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let final = cleaned.components(separatedBy: CharacterSet(charactersIn: "，, ")).first ?? cleaned
                if !final.isEmpty && final.count <= 20 { return final }
            }
        }
        return ""
    }
}

// MARK: - 导航状态

enum NavigationState: Equatable {
    case idle
    case locating
    case planning
    case navigating(remaining: CLLocationDistance, nextManeuver: String)
    case arrived
    case error(String)
}
