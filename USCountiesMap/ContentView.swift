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
    
    var body: some View {
        VStack {
//            LegacyMapView(polygons: data)
//                .ignoresSafeArea()
            
            Canvas { context, size in
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
                        let points = polygon.points()
                        let count = polygon.pointCount
                        if count == 0 { continue }
                        
                        // 2. Create a SwiftUI Path
                        var path = Path()
                        
                        for i in 0..<count {
                            let mapPoint = points[i]
                            
                            // 3. Map the MKMapPoint to the Canvas 'size'
                            let x = ((mapPoint.x - worldRect.origin.x) / worldRect.size.width) * size.width
                            let y = ((mapPoint.y - worldRect.origin.y) / worldRect.size.height) * size.height
                            
                            let point = CGPoint(x: x, y: y)
                            
                            if i == 0 {
                                path.move(to: point)
                            } else {
                                path.addLine(to: point)
                            }
                        }
                        
                        path.closeSubpath()
                        
                        // 4. Draw using the SwiftUI GraphicsContext
    //                            let color = colorFromCSV(county.fips) // Your custom color logic
                        
    //                            context.fill(path, with: .color(color))
                        context.stroke(path, with: .color(.black), lineWidth: 0.2)
                    }
                }
            }
            .aspectRatio(mapRatio(), contentMode: .fit)
            // Attach a DragGesture to the Canvas
            .gesture(DragGesture(minimumDistance: 0) // minimumDistance: 0 allows immediate tap recognition
                .onChanged { value in
                    // Append the current touch location to the array
//                    locations.append(value.location)
                }
                .onEnded { value in
                    // Optional: perform an action when the gesture ends
                    print("Drawing ended")
                }
            )
            
//            Text("Loaded \(data.count) counties")
//                .padding()
        }
        .task {
            await loadCounties()
        }
    }
    
    private func mapRatio() -> CGFloat {
        guard !worldRect.isNull, worldRect.size.height > 0 else { return CGFloat(1.0) }
        return CGFloat(worldRect.size.width / worldRect.size.height)
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
                
                let county = County(polygon : geometry, attributes: attributes)
                counties.append(county)
            }
            
            // If we got a full page, there's likely more.
            // If we got fewer than 2000, we've hit the end.
            if objects.count == pageSize {
                offset += pageSize
            } else {
                moreRecordsAvailable = false
            }
        }
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
