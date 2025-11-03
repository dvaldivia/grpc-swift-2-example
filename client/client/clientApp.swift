//
//  clientApp.swift
//  client
//
//  Created by Daniel Valdivia on 10/31/25.
//

import SwiftUI

@main
struct clientApp: App {
    var body: some Scene {
        WindowGroup {
            if #available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *) {
                ContentView()
            } else {
                ContentViewFallback()
            }
        }
    }
}
