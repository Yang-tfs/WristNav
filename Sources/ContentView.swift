import SwiftUI
import MapKit
import Combine

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 状态卡片
                statusCard

                // 目的地搜索
                VStack(alignment: .leading, spacing: 8) {
                    Text("目的地").font(.subheadline).foregroundColor(.secondary)
                    HStack {
                        TextField("输入地址或地点名称", text: $viewModel.searchQuery)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onSubmit { viewModel.search() }
                        Button("搜索") { viewModel.search() }
                            .buttonStyle(.borderedProminent)
                    }

                    if !viewModel.searchResults.isEmpty {
                        List(viewModel.searchResults, id: \.self) { item in
                            Button {
                                viewModel.selectDestination(item)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(item.name ?? "未知地点").font(.body)
                                    Text(item.placemark.title ?? "").font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                        .frame(maxHeight: 180)
                    }
                }

                if let dest = viewModel.selectedDestination {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("已选目的地").font(.caption).foregroundColor(.secondary)
                        Text(dest.name ?? "").font(.body)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }

                Spacer()

                // 控制按钮
                HStack(spacing: 16) {
                    Button(action: viewModel.toggleNavigation) {
                        Text(viewModel.isNavigating ? "结束导航" : "开始导航")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(viewModel.isNavigating ? Color.red : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .disabled(!viewModel.canStart && !viewModel.isNavigating)
                }

                // 权限提示
                if viewModel.showPermissionHint {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("首次使用需在 设置 中开启：").font(.caption)
                        Text("• 定位服务 → 始终").font(.caption)
                        Text("• 通知 → 允许").font(.caption)
                        Text("• 后台App刷新 → 开启").font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundColor(.orange)
                }
            }
            .padding()
            .navigationTitle("腕上导航")
            .onAppear { viewModel.checkPermissions() }
        }
    }

    private var statusCard: some View {
        VStack(spacing: 8) {
            switch viewModel.state {
            case .idle:
                Text("准备就绪").font(.headline)
                Text("输入目的地开始导航，转向提示将推送到手表")
                    .font(.caption).foregroundColor(.secondary)
            case .locating:
                ProgressView().scaleEffect(0.8)
                Text("正在定位…").font(.subheadline)
            case .planning:
                ProgressView().scaleEffect(0.8)
                Text("正在规划路线…").font(.subheadline)
            case .navigating(let remaining, let next):
                Text(next).font(.title2).bold()
                Text("剩余 \(formatDistance(remaining))")
                    .font(.subheadline).foregroundColor(.secondary)
                Text("通知已推送到手表")
                    .font(.caption).foregroundColor(.green)
            case .arrived:
                Text("已到达目的地").font(.title2).bold().foregroundColor(.green)
            case .error(let message):
                Text(message).font(.subheadline).foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func formatDistance(_ meters: CLLocationDistance) -> String {
        meters >= 1000 ? String(format: "%.1f 公里", meters / 1000) : "\(Int(meters)) 米"
    }
}

// MARK: - ViewModel

@MainActor
final class ContentViewModel: ObservableObject {
    @Published var searchQuery = ""
    @Published var searchResults: [MKMapItem] = []
    @Published var selectedDestination: MKMapItem?
    @Published var state: NavigationState = .idle
    @Published var showPermissionHint = false

    private var cancellables = Set<AnyCancellable>()

    init() {
        NavigationEngine.shared.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.state = $0 }
            .store(in: &cancellables)
    }

    var isNavigating: Bool {
        if case .navigating = state { return true }
        return false
    }

    var canStart: Bool { selectedDestination != nil }

    func checkPermissions() {
        showPermissionHint = true   // 首次启动始终显示权限指引，用户熟悉后可自行忽略
    }

    func search() {
        guard !searchQuery.isEmpty else { return }
        RoutePlanner.shared.search(query: searchQuery) { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let items) = result {
                    self?.searchResults = items
                }
            }
        }
    }

    func selectDestination(_ item: MKMapItem) {
        selectedDestination = item
        searchResults = []
        searchQuery = item.name ?? ""
    }

    func toggleNavigation() {
        if isNavigating {
            NavigationEngine.shared.stop()
        } else if let dest = selectedDestination {
            NavigationEngine.shared.start(destination: dest)
        }
    }
}
