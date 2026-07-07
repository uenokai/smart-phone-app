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
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        // ユーザー位置でマップをセンタリング
        if let userLocation = viewModel.userLocation {
            let region = MKCoordinateRegion(
                center: userLocation,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
            uiView.setRegion(region, animated: true)
        }

        // 既存のアノテーションを削除
        uiView.removeAnnotations(uiView.annotations.filter { !($0 is MKUserLocation) })

        // 新しいピンを追加
        let annotations = places.map { place -> MKPointAnnotation in
            let annotation = MKPointAnnotation()
            annotation.coordinate = CLLocationCoordinate2D(
                latitude: place.latitude,
                longitude: place.longitude
            )
            annotation.title = place.name
            annotation.subtitle = place.address
            return annotation
        }

        uiView.addAnnotations(annotations)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        let viewModel: MapViewModel

        init(viewModel: MapViewModel) {
            self.viewModel = viewModel
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }

            let annotationView = mapView.dequeueReusableAnnotationView(
                withIdentifier: "PlacePin",
                for: annotation
            ) as? MKMarkerAnnotationView

            annotationView?.markerTintColor = .systemBlue
            annotationView?.glyphText = "📍"
            return annotationView
        }
    }
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
                openingHours: nil,
                website: nil,
                phoneNumber: nil,
                reviews: nil
            )
        ]
    )
}
