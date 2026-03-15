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
                LinearGradient(
                    stops: (0...60).map { i in
                        let t = Double(i) / 60
                        let eased = t * t * (3 - 2 * t)
                        return .init(
                            color: .black.opacity(0.295 * (1 - eased)),
                            location: t
                        )
                    },
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .edgesIgnoringSafeArea(.all)
    }
}
