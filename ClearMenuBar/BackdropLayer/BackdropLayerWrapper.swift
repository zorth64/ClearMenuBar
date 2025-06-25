//
//  BackdropLayerWrapper.swift
//  ClearMenuBar
//
//  Created by zorth64 on 24/06/25.
//

import SwiftUI

struct BackdropLayerWrapper: NSViewRepresentable {
    var effect: BackdropLayerView.Effect

    func makeNSView(context: Context) -> BackdropLayerView {
        let backdropView = BackdropLayerView()
        backdropView.effect = effect
        backdropView.layerUsesCoreImageFilters = true
        return backdropView
    }

    func updateNSView(_ nsView: BackdropLayerView, context: Context) {
        nsView.effect = effect
        nsView.layerUsesCoreImageFilters = true
    }
}
