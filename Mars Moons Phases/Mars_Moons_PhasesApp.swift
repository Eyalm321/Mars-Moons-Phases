//
//  Mars_Moons_PhasesApp.swift
//  Mars Moons Phases
//
//  Created by Eyal Mizrachi on 3/24/24.
//

import SwiftUI
import Combine

class DeviceOrientation: ObservableObject {
    @Published var isLandscape: Bool = UIDevice.current.orientation.isLandscape
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        self.listenToDeviceOrientationChanges()
    }
    
    private func listenToDeviceOrientationChanges() {
        NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
            .map { _ -> Bool in
                        let isLandscape = UIDevice.current.orientation.isLandscape
                        print("Device orientation is now: \(isLandscape ? "Landscape" : "Portrait")")
                        return isLandscape
                    }
            .assign(to: \.isLandscape, on: self)
            .store(in: &cancellables)
    }
}

@main
struct Mars_Moons_PhasesApp: App {
    @StateObject private var deviceOrientation = DeviceOrientation()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(deviceOrientation)
        }
    }
}
