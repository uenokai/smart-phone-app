import SwiftUI
import MapKit

/// MapKitを使用したマップ表示ビュー
struct MapView: UIViewRepresentable {
    @ObservedObject var viewModel: MapViewModel
    var results: [ScoredPlace]

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "PlacePin")
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        // 初回のみユーザー位置でセンタリング（以降は手動でのパン・ズームを尊重する）
        if let userLocation = viewModel.userLocation, !context.coordinator.hasCenteredOnUser {
            context.coordinator.hasCenteredOnUser = true
            let region = MKCoordinateRegion(
                center: userLocation,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
            uiView.setRegion(region, animated: false)
        }

        // 検索結果が変わったときだけピンを更新する
        let placeIds = results.map { $0.id }
        guard placeIds != context.coordinator.lastPlaceIds else { return }
        context.coordinator.lastPlaceIds = placeIds

        uiView.removeAnnotations(uiView.annotations.filter { !($0 is MKUserLocation) })

        // 新しいピンを追加（穴場は紫、未確認は青緑、それ以外は青）
        let annotations = results.map { scored -> PlaceAnnotation in
            let annotation = PlaceAnnotation()
            annotation.coordinate = CLLocationCoordinate2D(
                latitude: scored.place.latitude,
                longitude: scored.place.longitude
            )
            annotation.title = scored.place.name
            annotation.subtitle = scored.headline.isEmpty ? scored.place.address : scored.headline
            annotation.placeId = scored.id
            annotation.badge = scored.badge
            return annotation
        }

        uiView.addAnnotations(annotations)

        // 全ピンが収まるようにズームを調整
        if !annotations.isEmpty {
            uiView.showAnnotations(annotations, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        let viewModel: MapViewModel
        var hasCenteredOnUser = false
        var lastPlaceIds: [String] = []

        init(viewModel: MapViewModel) {
            self.viewModel = viewModel
        }

        /// ピンタップで詳細画面を開く
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation as? PlaceAnnotation else { return }
            let placeId = annotation.placeId
            // 選択状態を解除しておかないと同じピンを再タップできない
            mapView.deselectAnnotation(annotation, animated: false)
            Task { @MainActor in
                viewModel.selectPlace(id: placeId)
            }
        }

        /// パン・ズーム後の地図中心を記録（「この周辺で検索」の起点になる）
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let center = mapView.centerCoordinate
            Task { @MainActor in
                viewModel.mapCenter = center
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }

            let annotationView = mapView.dequeueReusableAnnotationView(
                withIdentifier: "PlacePin",
                for: annotation
            ) as? MKMarkerAnnotationView

            let badge: ScoredPlace.Badge = (annotation as? PlaceAnnotation)?.badge ?? ScoredPlace.Badge.none
            switch badge {
            case .hiddenGem:
                annotationView?.markerTintColor = .systemPurple
                annotationView?.glyphText = "💎"
            case .unverified:
                annotationView?.markerTintColor = .systemTeal
                annotationView?.glyphText = "🔍"
            case .none:
                annotationView?.markerTintColor = .systemBlue
                annotationView?.glyphText = "📍"
            }
            return annotationView
        }
    }
}

/// 判定結果と店IDを持たせたカスタムアノテーション
class PlaceAnnotation: MKPointAnnotation {
    var placeId: String = ""
    var badge: ScoredPlace.Badge = .none
}

#Preview {
    MapView(
        viewModel: MapViewModel(),
        results: []
    )
}
