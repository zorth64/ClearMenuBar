//
//  ContentView.swift
//  ClearMenuBar
//
//  Created by zorth64 on 24/06/25.
//

import SwiftUI
import Foundation

struct ContentView: View {
    var body: some View {
        BackdropLayerWrapper(effect: .clear)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .edgesIgnoringSafeArea(.all)
    }
}
