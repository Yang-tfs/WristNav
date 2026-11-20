import Foundation
import MapKit
import CoreLocation

/// 路线规划器：基于 MapKit（中国大陆使用高德数据），无需申请 API Key
final class RoutePlanner {

    static let shared = RoutePlanner()
    private init() {}

    /// 根据目的地名称搜索地点
    func search(query: String, completion: @escaping (Result<[MKMapItem], Error>) -> Void) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        // 限定在中国区域，避免搜索结果跑到境外
        request.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.8617, longitude: 104.1954),
            span: MKCoordinateSpan(latitudeDelta: 60, longitudeDelta: 60)
        )
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(response?.mapItems ?? []))
            }
        }
    }

    /// 规划从起点到终点的路线
    func plan(from origin: CLLocationCoordinate2D,
              to destination: CLLocationCoordinate2D,
              destinationName: String,
              completion: @escaping (Result<RouteInfo, Error>) -> Void) {

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .automobile   // 骑行用汽车路线更稳妥；步行可切换 .walking
        request.requestsAlternateRoutes = false

        let directions = MKDirections(request: request)
        directions.calculate { response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let route = response?.routes.first else {
                completion(.failure(NSError(domain: "WristNav", code: 1,
                                            userInfo: [NSLocalizedDescriptionKey: "未找到可用路线"])))
                return
            }
            let info = RouteInfo(route: route, destination: destination, destinationName: destinationName)
            completion(.success(info))
        }
    }

    /// 重新规划（偏航后使用）
    func replan(from origin: CLLocationCoordinate2D,
                to routeInfo: RouteInfo,
                completion: @escaping (Result<RouteInfo, Error>) -> Void) {
        plan(from: origin, to: routeInfo.destination,
             destinationName: routeInfo.destinationName, completion: completion)
    }
}
