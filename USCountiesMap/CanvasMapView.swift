//
//  CountyMapLoader.swift
//  USCountiesMap
//
//  Created by Ashkan Hosseini on 2/25/26.
//

import Foundation
import SwiftUI
import MapKit

struct CanvasMapView: View {
    @Binding var counties : [County]
    @Binding var worldRect: MKMapRect
    @Binding var interactionState : InteractionState
    @Binding var showSheet : Bool
    
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                context.translateBy(x: interactionState.offset.width + size.width / 2, y: interactionState.offset.height + size.height / 2)
                context.scaleBy(x: interactionState.scale, y: interactionState.scale)
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
                        
                        let isSelected = polygon === interactionState.selectedCounty?.polygon
                        context.fill(path, with: .color(isSelected ? .orange.opacity(0.6) : .blue.opacity(0.3)))
                        context.stroke(path, with: .color(isSelected ? .orange : .blue), lineWidth: 0.2 / interactionState.scale)
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
    }
    
    var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                interactionState.offset = CGSize(
                    width: interactionState.lastOffset.width + value.translation.width,
                    height: interactionState.lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in interactionState.lastOffset = interactionState.offset }
    }

    var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                interactionState.scale = interactionState.lastScale * value
            }
            .onEnded { _ in interactionState.lastScale = interactionState.scale }
    }
    
    private func handleTap(_ location: CGPoint, in size: CGSize) {
        // Reverse the zoom/pan math to find the "true" point in the geometry
        let adjustedX = (location.x - interactionState.offset.width - size.width / 2) / interactionState.scale + size.width / 2
        let adjustedY = (location.y - interactionState.offset.height - size.height / 2) / interactionState.scale + size.height / 2
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
                    interactionState.selectedCounty = county
                    showSheet = true
                    return
                }
            }
        }
        
        interactionState.selectedCounty = nil // Deselect if tap lands on empty space
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
            interactionState.scale = interactionState.defaultScale
            interactionState.lastScale = interactionState.defaultScale
            interactionState.offset = .zero
            interactionState.lastOffset = .zero
        }
    }
}
