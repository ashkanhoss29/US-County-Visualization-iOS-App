//
//  LegacyMapView.swift
//  US Counties Map
//
//  Created by Ashkan Hosseini on 2/8/26.
//

import SwiftUI
import MapKit

struct LegacyMapView: UIViewRepresentable {
    let polygons: [County]

    // 1. Create the MKMapView (UIKit version)
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        return mapView
    }

    // 2. Handle updates
    func updateUIView(_ uiView: MKMapView, context: Context) {
        // Clear existing to avoid stacking
        uiView.removeOverlays(uiView.overlays)
        
        // Add the polygons from your array
        let mkPolygons = polygons.map { $0.polygon }
        uiView.addOverlays(mkPolygons)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let renderer: MKOverlayPathRenderer
                
                if let polygon = overlay as? MKPolygon {
                    renderer = MKPolygonRenderer(polygon: polygon)
                } else if let multiPolygon = overlay as? MKMultiPolygon {
                    renderer = MKMultiPolygonRenderer(multiPolygon: multiPolygon)
                } else {
                    return MKOverlayRenderer(overlay: overlay)
                }

                // Apply styles once to the base class (MKOverlayPathRenderer)
                renderer.fillColor = UIColor.systemBlue.withAlphaComponent(0.2)
                renderer.strokeColor = UIColor.systemBlue
                renderer.lineWidth = 0.4
            
                return renderer
        }
    }
}
