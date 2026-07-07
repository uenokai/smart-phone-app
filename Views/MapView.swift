import SwiftUI
import MapKit

/// MapKitを使用したマップ表示ビュー
struct MapView: UIViewRepresentable {
    @ObservedObject var viewModel: MapViewModel
    var places: [Place]

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
        let placeIds = places.map { $0.id }
        guard placeIds != context.coordinator.lastPlaceIds else { return }
        context.coordinator.lastPlaceIds = placeIds

        uiView.removeAnnotations(uiView.annotations.filter { !($0 is MKUserLocation) })

        // 新しいピンを追加（穴場は紫ピンで区別）
        let annotations = places.map { place -> PlaceAnnotation in
            let annotation = PlaceAnnotation()
            annotation.coordinate = CLLocationCoordinate2D(
                latitude: place.latitude,
                longitude: place.longitude
            )
            annotation.title = place.name
            annotation.subtitle = place.address
            annotation.placeId = place.id
            annotation.isHiddenGem = RecommendationEngine.isHiddenGem(place)
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

            // 穴場は紫ピン＋💎、それ以外は青ピン
            let isHiddenGem = (annotation as? PlaceAnnotation)?.isHiddenGem ?? false
            annotationView?.markerTintColor = isHiddenGem ? .systemPurple : .systemBlue
            annotationView?.glyphText = isHiddenGem ? "💎" : "📍"
            return annotationView
        }
    }
}

/// 穴場情報と店IDを持たせたカスタムアノテーション
class PlaceAnnotation: MKPointAnnotation {
    var placeId: String = ""
    var isHiddenGem: Bool = false
}

#Preview {
    MapView(
        viewModel: MapViewModel(),
        places: [
            Place(
                id: "1",
                name: "Sample Restaurant",
                category: .restaurant,
                latitude: 35.6762,
                longitude: 139.7674,
                address: "Tokyo, Japan",
                priceLevel: 2,
                rating: 4.5,
                userRatingsTotal: 42,
                openingHours: nil,
                website: nil,
                phoneNumber: nil,
                reviews: nil
            )
        ]
    )
}
