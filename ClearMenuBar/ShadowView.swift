//
//  ShadowView.swift
//  ClearMenuBar
//
//  Created by zorth64 on 24/06/25.
//

import SwiftUI

struct ShadowView: View {
    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                LinearGradient(stops: [
                    Gradient.Stop(color: .black.opacity(0.295), location: 0.0),
                    Gradient.Stop(color: .black.opacity(0.25), location: 0.11),
                    Gradient.Stop(color: .black.opacity(0.193), location: 0.3),
                    Gradient.Stop(color: .black.opacity(0.097), location: 0.6),
                    Gradient.Stop(color: .black.opacity(0.048), location: 0.75),
                    Gradient.Stop(color: .clear, location: 1.0)
                ], startPoint: .init(x: 1, y: 0.3), endPoint: .init(x: 1, y: 1))
            }
            .edgesIgnoringSafeArea(.all)
    }
}
