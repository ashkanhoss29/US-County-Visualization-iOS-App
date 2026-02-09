//
//  ContentView.swift
//  US Counties Map
//
//  Created by Ashkan Hosseini on 5/20/25.
//

import SwiftUI
import MapKit

struct CountyAttributes: Codable {
    let NAME: String
    let FIPS: String
    let STATE_NAME: String
}

struct IdentifiablePolygon: Identifiable {
    let id = UUID()
    let polygon: MKOverlay
    let attributes: CountyAttributes
}

struct ContentView: View {
    @State private var identifiablePolygons : [IdentifiablePolygon] = []
    @State private var isLoading = false
    
    var body: some View {
        VStack {
            LegacyMapView(polygons: identifiablePolygons)
                .ignoresSafeArea()
            
            Text("Loaded \(identifiablePolygons.count) counties")
                .padding()
        }
        .task {
            await loadCounties()
        }
    }
    
    private func loadCounties() async {
        do {
            try await fetchArgGISCounties()
        } catch {
            print("Error loading counties: \(error.localizedDescription)")
        }
    }
    
    private func fetchArgGISCounties() async throws {
        var offset = 0
        let pageSize = 2000 // ArcGIS default limit
        var moreRecordsAvailable = true
            
        while moreRecordsAvailable {
            let urlString = "https://services.arcgis.com/P3ePLMYs2RVChkJx/arcgis/rest/services/USA_Counties_Generalized_Boundaries/FeatureServer/0/query?where=1%3D1&outFields=*&f=geojson&resultOffset=\(offset)&resultRecordCount=\(pageSize)&geometryPrecision=3"
            
            guard let url = URL(string: urlString) else { break }
            let (data, _) = try await URLSession.shared.data(from : url)
            let decoder = MKGeoJSONDecoder()
            let objects = try decoder.decode(data)
            for object in objects {
                guard let feature = object as? MKGeoJSONFeature,
                      let geometry = feature.geometry.first as? MKOverlay,
                      (geometry is MKPolygon || geometry is MKMultiPolygon) else {
                    print("Not a polygon type"); continue
                }
                guard let propertyData = feature.properties,
                      let attributes = try? JSONDecoder().decode(CountyAttributes.self, from : propertyData) else { print("Decode failed"); continue }
                let identifiablePolygon = IdentifiablePolygon(polygon : geometry, attributes: attributes)
                identifiablePolygons.append(identifiablePolygon)
            }
            
            // If we got a full page, there's likely more.
            // If we got fewer than 2000, we've hit the end.
            if identifiablePolygons.count == pageSize {
                offset += pageSize
            } else {
                moreRecordsAvailable = false
            }
        }
    }
}

struct CountyOverlay: View {
    let polygon: MKPolygon
    
    var body: some View {
        Circle()
            .fill(Color.blue.opacity(0.3))
            .frame(width: 5, height: 5)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
