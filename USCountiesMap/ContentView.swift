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

struct County: Identifiable {
    let id = UUID()
    var polygon: MKOverlay
    let attributes: CountyAttributes
}

struct ContentView: View {
    @State private var counties : [County] = []
    @State private var isLoading = false
    @State private var width : Double = 0
    @State private var height : Double = 0
    @State private var worldRect: MKMapRect = .null
    
    // Interaction State
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    // Selection State
    @State private var selectedCounty : County?
    @State private var showSheet = false
    
    var body: some View {
        VStack(spacing: 0) {
//            LegacyMapView(polygons: counties)
//                .ignoresSafeArea()
            HStack {
                VStack(alignment: .leading) {
                    Text("County Inspector")
                        .font(.headline)
                    Text("\(counties.count) counties loaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button(action: resetView) {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .disabled(scale == 1.0 && offset == .zero)
            }
            .padding()
            .background(.ultraThinMaterial)
            
            GeometryReader { geo in
                Canvas { context, size in
                    context.translateBy(x: offset.width + size.width / 2, y: offset.height + size.height / 2)
                    context.scaleBy(x: scale, y: scale)
                    context.translateBy(x: -size.width / 2, y: -size.height / 2)
                    
                    for county in counties {
                        var polygons : [MKPolygon] = []
                        
                        if let multiPolygon = county.polygon as? MKMultiPolygon {
                            for polygon in multiPolygon.polygons {
                                polygons.append(polygon)
                            }
                        }
                        
                        if let polygon = county.polygon as? MKPolygon {
                            polygons.append(polygon)
                        }
                        
                        for polygon in polygons {
                            let path = createPath(for: polygon, in: size, rect: worldRect)
                            
                            let isSelected = polygon === selectedCounty?.polygon
                            context.fill(path, with: .color(isSelected ? .orange.opacity(0.6) : .blue.opacity(0.3)))
                            context.stroke(path, with: .color(isSelected ? .orange : .blue), lineWidth: 0.2 / scale)
                        }
                    }
                }
                .gesture(dragGesture)
                .gesture(magnificationGesture)
                .onTapGesture { location in
                    handleTap(location, in: geo.size)
                }
            }
            .aspectRatio(mapRatio(), contentMode: .fit)
            .clipped()
            .background(Color(.systemGroupedBackground))
            
//            Text("Loaded \(data.count) counties")
//                .padding()
            
        }
        .sheet(isPresented: $showSheet, onDismiss: {
            selectedCounty = nil
        }) {
            PolygonDetailView(county: selectedCounty)
                .presentationDetents([.medium, .fraction(0.3)])
        }
        .task {
            await loadCounties()
        }
    }
    
    var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in lastOffset = offset }
    }

    var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = lastScale * value
            }
            .onEnded { _ in lastScale = scale }
    }
    
    private func handleTap(_ location: CGPoint, in size: CGSize) {
        // Reverse the zoom/pan math to find the "true" point in the geometry
        let adjustedX = (location.x - offset.width - size.width / 2) / scale + size.width / 2
        let adjustedY = (location.y - offset.height - size.height / 2) / scale + size.height / 2
        let hitPoint = CGPoint(x: adjustedX, y: adjustedY)

        // Check each polygon
        for county in counties {
            var polygons : [MKPolygon] = []
            
            if let multiPolygon = county.polygon as? MKMultiPolygon {
                for polygon in multiPolygon.polygons {
                    polygons.append(polygon)
                }
            }
            
            if let polygon = county.polygon as? MKPolygon {
                polygons.append(polygon)
            }
            
            for polygon in polygons {
                let path = createPath(for: polygon, in: size, rect: worldRect)
                if path.contains(hitPoint) {
                    selectedCounty = county
                    showSheet = true
                    return
                }
            }
        }
        
        selectedCounty = nil // Deselect if tap lands on empty space
    }
    
    private func createPath(for polygon: MKPolygon, in size: CGSize, rect: MKMapRect) -> Path {
        var path = Path()
        let points = polygon.points()
        for i in 0..<polygon.pointCount {
            let mp = points[i]
            let x = CGFloat((mp.x - rect.origin.x) / rect.size.width) * size.width
            let y = CGFloat((mp.y - rect.origin.y) / rect.size.height) * size.height
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath()
        return path
    }
    
    private func mapRatio() -> CGFloat {
        guard !worldRect.isNull, worldRect.size.height > 0 else { return CGFloat(1.0) }
        return CGFloat(worldRect.size.width / worldRect.size.height)
    }
    
    private func resetView() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            scale = 1.0
            lastScale = 1.0
            offset = .zero
            lastOffset = .zero
        }
    }
    
    private func loadCounties() async {
        do {
            try await fetchArgGISCounties()
            postProcess()
            let rect = counties.reduce(MKMapRect.null) { $0.union($1.polygon.boundingMapRect) }
            worldRect = rect
        } catch {
            print("Error loading counties: \(error.localizedDescription)")
        }
    }
    
    private func fetchArgGISCounties() async throws {
        var offset = 0
        let pageSize = 2000 // ArcGIS default limit
        var moreRecordsAvailable = true
            
        while moreRecordsAvailable {
            let localData = loadFromDisk(offset: offset)
            let data: Data
            
            if let cached = localData {
                // Found it on disk!
                data = cached
            } else {
                // Not on disk, fetch from network
                let urlString = "https://services.arcgis.com/P3ePLMYs2RVChkJx/arcgis/rest/services/USA_Counties_Generalized_Boundaries/FeatureServer/0/query?where=1%3D1&outFields=*&f=geojson&resultOffset=\(offset)&resultRecordCount=\(pageSize)&geometryPrecision=3"
                
                guard let url = URL(string: urlString) else { break }
                let (downloadedData, _) = try await URLSession.shared.data(from: url)
                data = downloadedData
                
                // Save to disk for next time
                saveToDisk(data: data, offset: offset)
            }
            
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
                
                let county = County(polygon : geometry, attributes: attributes)
                counties.append(county)
            }
            
            if objects.count == pageSize {
                offset += pageSize
            } else {
                moreRecordsAvailable = false
            }
        }
    }
    
    private func getLocalURL(for offset: Int) -> URL {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("counties_offset_\(offset).geojson")
    }

    private func saveToDisk(data: Data, offset: Int) {
        let url = getLocalURL(for: offset)
        try? data.write(to: url)
    }

    private func loadFromDisk(offset: Int) -> Data? {
        let url = getLocalURL(for: offset)
        return try? Data(contentsOf: url)
    }
    
    func postProcess() {
        counties = counties.map { county in
            var updatedCounty = county
            if updatedCounty.attributes.STATE_NAME == "Alaska" {
                updatedCounty.polygon = shiftAlaska(alaska: updatedCounty.polygon)
            } else if updatedCounty.attributes.STATE_NAME == "Hawaii" {
                updatedCounty.polygon = shiftHawaii(hawaii: updatedCounty.polygon)
            }
            return updatedCounty
        }
    }
    
    func shiftAlaska(alaska : MKOverlay) -> MKOverlay {
        let centerLat = 64.0, centerLon = -150.0
        let latOffset = -36.0, lonOffset = 34.0
        
        // We use a smaller horizontal scale to "squish" the Mercator stretch
        let scaleX = 0.20
        let scaleY = 0.35
        
        if let multiPolygon = alaska as? MKMultiPolygon {
            let shiftedPolygons = multiPolygon.polygons.map { polygon in
                return shiftPolygonWithXY(polygon, centerLat: centerLat, centerLon: centerLon, latOffset: latOffset, lonOffset: lonOffset, scaleX: scaleX, scaleY: scaleY)
            }
            return MKMultiPolygon(shiftedPolygons)
        } else if let polygon = alaska as? MKPolygon {
            let shiftedPolygons = shiftPolygonWithXY(polygon, centerLat: centerLat, centerLon: centerLon, latOffset: latOffset, lonOffset: lonOffset, scaleX: scaleX, scaleY: scaleY)
            return shiftedPolygons
        } else {
            return alaska
        }
    }
    
    func shiftHawaii(hawaii : MKOverlay) -> MKOverlay {
        let centerLat = 21.3, centerLon = -157.8
        let latOffset = 8.0, lonOffset = 50.0
        let scale = 1.0
        
        if let multiPolygon = hawaii as? MKMultiPolygon {
            let shiftedPolygons = multiPolygon.polygons.map { polygon in
                return shiftPolygonWithXY(polygon, centerLat: centerLat, centerLon: centerLon, latOffset: latOffset, lonOffset: lonOffset, scaleX : scale, scaleY : scale)
            }
            return MKMultiPolygon(shiftedPolygons)
        } else if let polygon = hawaii as? MKPolygon {
            return shiftPolygonWithXY(polygon, centerLat: centerLat, centerLon: centerLon, latOffset: latOffset, lonOffset: lonOffset, scaleX : scale, scaleY : scale)
        } else {
            return hawaii
        }
    }
    
    func shiftPolygonWithXY(_ polygon: MKPolygon, centerLat: Double, centerLon: Double, latOffset: Double, lonOffset: Double, scaleX: Double, scaleY: Double) -> MKPolygon {
        let pointCount = polygon.pointCount
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        polygon.getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        
        let transformedCoords = coords.map { coord -> CLLocationCoordinate2D in
            // Normalize Longitude for Alaska (Aleutian Islands fix)
            var lon = coord.longitude
            if lon > 0 { lon -= 360 }
            
            let newLat = centerLat + (coord.latitude - centerLat) * scaleY
            let newLon = centerLon + (lon - centerLon) * scaleX
            
            return CLLocationCoordinate2D(latitude: newLat + latOffset, longitude: newLon + lonOffset)
        }
        
        let interiorPolygons = polygon.interiorPolygons?.map {
            shiftPolygonWithXY($0, centerLat: centerLat, centerLon: centerLon, latOffset: latOffset, lonOffset: lonOffset, scaleX: scaleX, scaleY: scaleY)
        }
        
        return MKPolygon(coordinates: transformedCoords, count: pointCount, interiorPolygons: interiorPolygons)
    }
}

struct CountyOverlay: View {
    let polygon: County?
    
    var body: some View {
        Circle()
            .fill(Color.blue.opacity(0.3))
            .frame(width: 5, height: 5)
    }
}

struct PolygonDetailView: View {
    let county: County?
    
    // Access the dismiss action from the environment
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                if let county = county {
                    let poly = county.polygon
                    Section("Identity") {
                        LabeledContent("Title", value: county.attributes.FIPS)
//                        LabeledContent("Points", value: "\(poly.pointCount)")
                    }
                    
                    Section("Geography") {
                        // Centroid is roughly the middle of the bounding box
                        let center = poly.coordinate
                        LabeledContent("Latitude", value: String(format: "%.4f", center.latitude))
                        LabeledContent("Longitude", value: String(format: "%.4f", center.longitude))
                    }
                    
                    Section("Measurements") {
                        // Calculate area in Square Meters using the MapRect
                        let area = poly.boundingMapRect.size.width * poly.boundingMapRect.size.height
                        LabeledContent("Approx. Area", value: "\(Int(area).formatted()) m²")
                    }
                } else {
                    Text("No data available")
                }
            }
            .navigationTitle("Area Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.title3)
                    }
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
