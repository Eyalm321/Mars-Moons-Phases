import SwiftUI
import SceneKit
import Combine

class LoadingState: ObservableObject {
    @Published var isLoading = true
    
    func updateLoading(_ loading: Bool) {
        DispatchQueue.main.async {
            self.isLoading = loading
        }
    }
}

extension UIColor {
    convenience init(hex: String) {
        let hexString = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int = UInt64()
        Scanner(string: hexString).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hexString.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}

import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue:  Double(b) / 255, opacity: Double(a) / 255)
    }
}

struct Moon {
    let name: String
    let radius: String?
    let density: String?
    var orbitalPeriodDays: Double?
    var orbitalPeriodHours: Double?
    
    init(name: String, radius: String = "", density: String = "", orbitalPeriod: String = "") {
        self.name = name
        self.radius = radius
        self.density = density
        
        let parts = orbitalPeriod.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 2 {
            if let daysPart = Double(parts[0].components(separatedBy: " ").first ?? "0"),
               let hoursPart = Double(parts[1].components(separatedBy: " ").first ?? "0") {
                self.orbitalPeriodDays = daysPart
                self.orbitalPeriodHours = hoursPart
            } else {
                self.orbitalPeriodDays = 0
                self.orbitalPeriodHours = 0
            }
        } else {
            self.orbitalPeriodDays = 0
            self.orbitalPeriodHours = 0
        }
    }
}

struct PositionVector: Codable {
    var x: Double
    var y: Double
    var z: Double
    var vx: Double
    var vy: Double
    var vz: Double
    
    init(x: Double, y: Double, z: Double, vx: Double, vy: Double, vz: Double) {
        self.x = x
        self.y = y
        self.z = z
        self.vx = vx
        self.vy = vy
        self.vz = vz
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        z = try container.decode(Double.self, forKey: .z)
        vx = try container.decode(Double.self, forKey: .vx)
        vy = try container.decode(Double.self, forKey: .vy)
        vz = try container.decode(Double.self, forKey: .vz)
    }
    
    func toSCNVector3() -> SCNVector3 {
        return SCNVector3(x: Float(x), y: Float(y), z: Float(z))
    }
    
    static func from(scnVector: SCNVector3) -> PositionVector {
        
        return PositionVector(x: Double(scnVector.x), y: Double(scnVector.y), z: Double(scnVector.z), vx: 0, vy: 0, vz: 0)
    }
}

struct CacheManager {
    static let shared = CacheManager()
    
    func cacheData(forMoon moonId: String, date: Date, data: Data) {
        let cacheKey = generateCacheKey(forMoon: moonId, date: date)
        UserDefaults.standard.setValue(data, forKey: cacheKey)
    }
    
    func getCachedData(forMoon moonId: String, date: Date) -> Data? {
        let cacheKey = generateCacheKey(forMoon: moonId, date: date)
        return UserDefaults.standard.data(forKey: cacheKey)
    }
    
    func removeCachedData(forMoon moonId: String, date: Date) {
        let cacheKey = generateCacheKey(forMoon: moonId, date: date)
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }
    
    private func generateCacheKey(forMoon moonId: String, date: Date) -> String {
        let dateKey = formatDate(date)
        return "NASADataCache_\(moonId)_\(dateKey)"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }
}

extension String {
    func toDouble() -> Double? {
        return Double(self)
    }
}

class NASA_API {
    static let shared = NASA_API()
    
    let bodyIds = ["Phobos": "401", "Deimos": "402", "Mars": "499", "Sun": "10"]
    let cache = CacheManager.shared
    
    private func buildHorizonsURL(forBody bodyId: String, relativeTo centerId: String, startDate: Date, endDate: Date) -> URL? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let startTime = dateFormatter.string(from: startDate)
        let stopTime = dateFormatter.string(from: endDate)
        
        var components = URLComponents(string: "https://ssd.jpl.nasa.gov/api/horizons.api")
        components?.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "COMMAND", value: "'\(bodyId)'"),
            URLQueryItem(name: "MAKE_EPHEM", value: "YES"),
            URLQueryItem(name: "EPHEM_TYPE", value: "VECTORS"),
            URLQueryItem(name: "CENTER", value: "'\(centerId)'"),
            URLQueryItem(name: "START_TIME", value: "'\(startTime)'"),
            URLQueryItem(name: "STOP_TIME", value: "'\(stopTime)'"),
            URLQueryItem(name: "STEP_SIZE", value: "'1d'"),
            URLQueryItem(name: "OUT_UNITS", value: "'AU-D'")
        ]
        return components?.url
    }
    
    func fetchEphemerisData(bodies: [String], relativeTo centerId: String, startDate: Date, completion: @escaping (Result<[String: String], Error>) -> Void) {
        let group = DispatchGroup()
        var results = [String: String]()
        var lastError: Error?
        
        for body in bodies {
            group.enter()
            guard let bodyId = self.bodyIds[body] else {
                print("Invalid body ID for \(body)")
                group.leave()
                continue
            }
            
            if let cachedData = self.cache.getCachedData(forMoon: bodyId, date: startDate), let cachedString = String(data: cachedData, encoding: .utf8) {
                results[body] = cachedString
                group.leave()
                continue
            }
            
            self.fetchEphemerisDataForBody(bodyId: bodyId, relativeTo: centerId, startDate: startDate) { result in
                defer { group.leave() }
                switch result {
                case .success(let responseString):
                    results[body] = responseString
                    
                    if let dataToCache = responseString.data(using: .utf8) {
                        self.cache.cacheData(forMoon: bodyId, date: startDate, data: dataToCache)
                    }
                case .failure(let error):
                    lastError = error
                }
            }
        }
        
        group.notify(queue: .main) {
            if let error = lastError {
                completion(.failure(error))
            } else {
                completion(.success(results))
            }
        }
    }
    
    func fetchEphemerisDataForBody(bodyId: String, relativeTo centerId: String, startDate: Date, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = buildHorizonsURL(forBody: bodyId, relativeTo: centerId, startDate: startDate, endDate: Calendar.current.date(byAdding: .day, value: 1, to: startDate)!) else {
            completion(.failure(NSError(domain: "Invalid URL", code: -1, userInfo: nil)))
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                completion(.failure(error ?? NSError(domain: "Network error", code: -2, userInfo: nil)))
                return
            }
            
            guard let responseString = String(data: data, encoding: .utf8) else {
                completion(.failure(NSError(domain: "Data Encoding Error", code: -3, userInfo: nil)))
                return
            }
            
            completion(.success(responseString))
        }
        task.resume()
    }
    
    func fetchSunPositionRelativeToMoon(moonName: String, on inputDate: Date, completion: @escaping (Result<SCNVector3, Error>) -> Void) {
        guard let moonId = bodyIds[moonName], let sunId = bodyIds["Sun"] else {
            let error = NSError(domain: "NASA_API", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid body ids"])
            completion(.failure(error))
            return
        }
        
        
        if let cachedData = CacheManager.shared.getCachedData(forMoon: moonId, date: inputDate),
           let cachedPositionVector = try? JSONDecoder().decode(PositionVector.self, from: cachedData) {
            
            completion(.success(cachedPositionVector.toSCNVector3()))
            return
        }
        
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        guard let date = dateFormatter.date(from: dateFormatter.string(from: inputDate)) else {
            let error = NSError(domain: "NASA_API", code: 2, userInfo: [NSLocalizedDescriptionKey: "Date formatting error"])
            completion(.failure(error))
            print("API Call Failed with error: \(error)")
            return
        }
        
        fetchEphemerisDataForBody(bodyId: moonId, relativeTo: sunId, startDate: date) { [weak self] result in
            switch result {
            case .success(let responseString):
                self?.handleSuccess(responseString: responseString, moonId: moonId, date: date, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    private func handleSuccess(responseString: String, moonId: String, date: Date, completion: @escaping (Result<SCNVector3, Error>) -> Void) {
        guard let positionVector = parsePositionVector(fromApiResponse: responseString) else {
            let error = NSError(domain: "NASA_API", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to parse position vector"])
            completion(.failure(error))
            return
        }
        
        let scalingFactor: Float = 1.0
        let position = SCNVector3(
            x: Float(positionVector.x) * 149597870.7 * scalingFactor,
            y: Float(positionVector.y) * 149597870.7 * scalingFactor,
            z: Float(positionVector.z) * 149597870.7 * scalingFactor
        )
        
        
        if let dataToCache = try? JSONEncoder().encode(positionVector) {
            CacheManager.shared.cacheData(forMoon: moonId, date: date, data: dataToCache)
        }
        
        completion(.success(position))
    }
    
    private func extractFirstMatch(for pattern: String, in text: String) -> String? {
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let nsRange = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: nsRange),
                  let range = Range(match.range(at: 1), in: text) else {
                return nil
            }
            
            return String(text[range])
        } catch {
            print("Regex error: \(error)")
            return nil
        }
    }
    
    func parsePositionVector(fromApiResponse response: String) -> PositionVector? {
        guard let data = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let resultString = json["result"] as? String else {
            print("Failed to parse JSON or extract 'result' with response: \(response)")
            return nil
        }
        
        let pattern = #"(X|Y|Z|VX|VY|VZ)\s*=\s*([-]?\d+\.\d+E[+-]\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            print("Failed to create regex")
            return nil
        }
        
        var vectorValues = [String: Double]()
        
        let matches = regex.matches(in: resultString, options: [], range: NSRange(resultString.startIndex..., in: resultString))
        for match in matches where match.numberOfRanges == 3 {
            let keyRange = Range(match.range(at: 1), in: resultString)!
            let valueRange = Range(match.range(at: 2), in: resultString)!
            
            let key = String(resultString[keyRange])
            if let value = Double(resultString[valueRange]) {
                vectorValues[key] = value
            }
        }
        
        let requiredKeys = ["X", "Y", "Z", "VX", "VY", "VZ"]
        for key in requiredKeys {
            if vectorValues[key] == nil {
                print("Missing key: \(key)")
                return nil
            }
        }
        
        
        guard let x = vectorValues["X"], let y = vectorValues["Y"], let z = vectorValues["Z"],
              let vx = vectorValues["VX"], let vy = vectorValues["VY"], let vz = vectorValues["VZ"] else {
            print("Failed to extract all components")
            return nil
        }
        
        let positionVector = PositionVector(x: x, y: y, z: z, vx: vx, vy: vy, vz: vz)
        return positionVector
    }
    
    func fetchMarsPositionRelativeToMoon(moonName: String, on inputDate: Date, completion: @escaping (Result<SCNVector3, Error>) -> Void) {
        guard let moonId = bodyIds[moonName], let marsId = bodyIds["Mars"] else {
            let error = NSError(domain: "NASA_API", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid body ids"])
            completion(.failure(error))
            return
        }
        
        
        if let cachedData = CacheManager.shared.getCachedData(forMoon: moonId, date: inputDate),
           let cachedPositionVector = try? JSONDecoder().decode(PositionVector.self, from: cachedData) {
            
            completion(.success(cachedPositionVector.toSCNVector3()))
            return
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        guard let date = dateFormatter.date(from: dateFormatter.string(from: inputDate)) else {
            let error = NSError(domain: "NASA_API", code: 2, userInfo: [NSLocalizedDescriptionKey: "Date formatting error"])
            completion(.failure(error))
            print("API Call Failed with error: \(error)")
            return
        }
        
        fetchEphemerisDataForBody(bodyId: marsId, relativeTo: moonId, startDate: date) { [weak self] result in
            switch result {
            case .success(let responseString):
                self?.handleSuccess(responseString: responseString, moonId: moonId, date: date, completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

extension Double {
    
    var degreesToRadians: Double {
        return self * .pi / 180
    }
}

extension Float {
    var degreesToRadians: Float {
        return self * .pi / 180
    }
}

struct InfoPopupView: View {
    @Binding var showingAppDetails: Bool
    @EnvironmentObject var deviceOrientation: DeviceOrientation
    
    var body: some View {
        VStack(spacing: 0) {
            Group {
                if deviceOrientation.isLandscape {
                    ScrollView { message }
                        .padding(.top, 1)
                } else {
                    message
                }
            }
            closeButton
        }
        .frame(maxWidth: 600)
        .background(Color(hex: "F6F6F8"))
        .cornerRadius(20)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .shadow(radius: 10)
    }
    
    private var message: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The Process").font(.title).bold()
            Group {
                Text("Hello Yohai and the ATT Crew 👋🏻")
                Text("I built this app using SwiftUI & SceneKit.")
                Text("Its a simulation of Mars moons orbital characteristics.")
                Text("The goal is to demonstrate my abilities to control both 2D and 3D elements in view, as well as data fetching and manipulation. I'm using NASA Horizons Api to fetch real-time data about positions of celestial bodies in space and simulate those positions in the form of lights (Mars/Sun reflection).")
                Text("Model was also downloaded from NASA and was edited using Blender & Adobe Substance Painter to get high-resolution texture and nicer curvatures.")
                Text("I made the code available on Github, you can reach it by clicking on the github icon in the left top corner.")
            }
            .padding(.bottom, 5)
        }
        .padding()
    }
    
    private var closeButton: some View {
        Button("Close") {
            showingAppDetails = false
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.blue)
        .foregroundColor(.white)
        .cornerRadius(10)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}

struct ContentView: View {
    @EnvironmentObject private var deviceOrientation: DeviceOrientation
    @State private var selectedMoon: Moon
    @State private var marsYear = 0
    @State private var sol = 0
    @StateObject var loadingState = LoadingState()
    @State private var showingAppDetails = false
    let dateChangeRate: Double = 0.001
    @StateObject private var simulationState: SimulationState = SimulationState(selectedMoon: Moon(name: "Unknown", orbitalPeriod: "0 days / 0 Hours"))
    var dateUtil = Date()
    
    let moons: [Moon]
    
    init() {
        let defaultMoons = [
            Moon(name: "Phobos", radius: "13.1 x 11.1 x 9.3 km", density: "1.90 ± 0.08 g/cm³", orbitalPeriod: "0.3 days / 7 Hours"),
            Moon(name: "Deimos", radius: "7.8 x 6.0 x 5.1 km", density: "1.76 ± 0.30 g/cm³", orbitalPeriod: "1.2 days / 30 Hours")
        ]
        self.moons = defaultMoons
        _selectedMoon = State(initialValue: defaultMoons.first ?? Moon(name: "Unknown"))
    }
    
    var body: some View {
        ZStack {
            Image("Space")
                .resizable()
                .ignoresSafeArea()
            
            Moon3DView(simulationState: simulationState, selectedMoon: $selectedMoon, dateChangeRate: dateChangeRate, globalLoadingState: loadingState)
            
            VStack {
                customToolbar.padding()
                MoonHeaderView(selectedMoon: $selectedMoon, moons: moons)
                Spacer()
            }
            
            if showingAppDetails {
                InfoPopupView(showingAppDetails: $showingAppDetails)
                    .onTapGesture {
                        showingAppDetails = false
                    }
                    .zIndex(2)
            }
            
            GeometryReader { geometry in
                MoonInfoView(simulationState: simulationState, moon: $selectedMoon)
                    .position(x: geometry.size.width / 2, y: geometry.size.height - (geometry.size.height / (deviceOrientation.isLandscape ? 2 : 3) / 2))
                    .edgesIgnoringSafeArea(.bottom)
            }
            .zIndex(1)
        }
        .onAppear {
            let (year, sol) = simulationState.date.getMarsTime()
            self.marsYear = year
            self.sol = sol
        }
        .onChange(of: simulationState.date) { newDate, _ in
            let (year, sol) = simulationState.date.getMarsTime()
            self.marsYear = year
            self.sol = sol
        }
    }
    
    var customToolbar: some View {
        HStack {
            Button(action: {
                if let url = URL(string: "https://github.com/Eyalm321/Mars-Moons-Phases") {
                    UIApplication.shared.open(url)
                }
            }) {
                Image("Github")
                    .resizable()
                    .frame(width: 24, height: 24)
                    .accessibilityLabel("GitHub")
            }
            
            Spacer()
            
            VStack {
                Text("Mars Moons Phases").font(.headline).foregroundStyle(.white)
                Text(simulationState.date, style: .date).font(.caption).foregroundStyle(.white)
                Text("MY: \(marsYear) Sol: \(sol)").font(.caption).foregroundStyle(.white)
            }
            
            Spacer()
            
            Button(action: {
                withAnimation {
                    showingAppDetails.toggle()
                }
            }) {
                Image(systemName: "questionmark.circle")
                    .resizable()
                    .frame(width: 24, height: 24)
                    .accessibilityLabel("Show app details")
            }
        }
        .padding()
        .background(Color.black.opacity(0.5))
    }
}

struct MoonHeaderView: View {
    @EnvironmentObject var deviceOrientation: DeviceOrientation
    @Binding var selectedMoon: Moon
    var moons: [Moon]
    
    var body: some View {
        VStack {
            HStack(spacing: 20) {
                if !deviceOrientation.isLandscape { Spacer() }
                ForEach(moons, id: \.name) { moon in
                    Text(moon.name)
                        .zIndex(1.0)
                        .padding()
                        .frame(minWidth: 100, minHeight: 44)
                        .foregroundColor(selectedMoon.name == moon.name ? .black : .white)
                        .background(selectedMoon.name == moon.name ? Color(hex: "F6F6F8") : Color(hex: "000000"))
                        .cornerRadius(8)
                        .onTapGesture {
                            self.selectedMoon = moon
                        }
                }
                
                if !deviceOrientation.isLandscape { Spacer() }
            }
            .padding(.horizontal, deviceOrientation.isLandscape ? 64 : 0)
        }
        .frame(width: UIScreen.main.bounds.width, alignment: !deviceOrientation.isLandscape ? .center : .leading)
        
        .onChange(of: deviceOrientation.isLandscape) { _, newValue in
            //            print("Device orientation is now: \(newValue ? "Landscape" : "Portrait")")
        }
    }
    
    func estimatedContentWidth() -> CGFloat {
        let itemWidth: CGFloat = 100
        let totalContentWidth = CGFloat(moons.count) * itemWidth
        return totalContentWidth
    }
}

class SimulationState: ObservableObject {
    var selectedMoon: Moon
    @Published var cumulativeRotationDegrees: Double = 0 {
        didSet {
            checkForOrbitCompletion()
        }
    }
    @Published var cumulativeRotationHours: Double = 0
    @Published var rotationCount: Double = 0
    @Published var date: Date = Date()
    
    init(selectedMoon: Moon) {
        self.selectedMoon = selectedMoon
    }
    
    func updateRotation(with speed: Double) {
        guard let orbitalPeriodHours = selectedMoon.orbitalPeriodHours else { return }
        
        let additionalRotationHours = speed * orbitalPeriodHours
        cumulativeRotationHours += additionalRotationHours
        
        let degreesPerHour = 360 / orbitalPeriodHours
        let additionalDegrees = additionalRotationHours * degreesPerHour
        cumulativeRotationDegrees += additionalDegrees
        let completedOrbits = Int(cumulativeRotationHours / orbitalPeriodHours)
        rotationCount += Double(completedOrbits)
        cumulativeRotationHours -= Double(completedOrbits) * orbitalPeriodHours
        
        checkForOrbitCompletion()
    }
    
    func checkForOrbitCompletion() {
        guard let orbitalPeriodHours = selectedMoon.orbitalPeriodHours, orbitalPeriodHours != 0 else { return }
        
        let orbitCountInDay = 24 / orbitalPeriodHours
        let completedOrbits = abs(rotationCount)
        
        if completedOrbits >= orbitCountInDay {
            let daysChange = Int(rotationCount / orbitCountInDay)
            if let newDate = Calendar.current.date(byAdding: .day, value: daysChange, to: date) {
                date = newDate
                rotationCount -= Double(daysChange) * orbitCountInDay
                cumulativeRotationHours = rotationCount * orbitalPeriodHours
            }
        }
    }
}

extension Date {
    func resetTime() -> Date? {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: self)
        return calendar.date(from: components)
    }
    
    func getMarsTime() -> (marsYear: Int, sol: Int) {
        let calendar = Calendar(identifier: .gregorian)
        let my1StartDateComponents = DateComponents(year: 1955, month: 4, day: 11)
        guard let my1StartDate = calendar.date(from: my1StartDateComponents) else {
            fatalError("Failed to create MY1 start date.")
        }
        
        let daysSinceMy1Start = calendar.dateComponents([.day], from: my1StartDate, to: self).day ?? 0
        let marsYear = 1 + daysSinceMy1Start / 687
        let sol = (daysSinceMy1Start % 687) + 1
        
        return (marsYear, sol)
    }
}

struct Moon3DView: View {
    @ObservedObject var simulationState: SimulationState
    @EnvironmentObject var deviceOrientation: DeviceOrientation
    @Binding var selectedMoon: Moon
    let dateChangeRate: Double
    @State private var rotation = SCNVector3(0, 0, 0)
    @State private var initialTouchLocation: CGPoint = .zero
    @ObservedObject var globalLoadingState = LoadingState()
    
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                TransparentSceneView(
                    simulationState: simulationState,
                    selectedMoon: $selectedMoon,
                    dateChangeRate: dateChangeRate,
                    globalLoadingState: globalLoadingState
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                .aspectRatio(0.8, contentMode: .fit)
                .gesture(dragGesture())
            }
            
            if globalLoadingState.isLoading {
                VStack {
                    Spacer()
                    HStack {
                        Text("Loading real-time data...")
                            .foregroundColor(.white)
                            .padding(.trailing, 8)
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color.white))
                    }
                    .padding(.bottom, 96)
                    .padding(.trailing, 16)
                }
                .frame(maxWidth: .infinity, alignment: .bottomTrailing)
            }
        }
    }
    
    private func dragGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let dragDirection = value.translation.width > 0 ? 1 : -1
                let rotationSpeed = 0.025 * Double(dragDirection)
                self.simulationState.updateRotation(with: rotationSpeed)
            }
    }
    
    struct TransparentSceneView: UIViewRepresentable {
        @EnvironmentObject var deviceOrientation: DeviceOrientation
        @ObservedObject var simulationState: SimulationState
        @Binding var selectedMoon: Moon
        let dateChangeRate: Double
        
        @ObservedObject var globalLoadingState: LoadingState
        
        func makeUIView(context: Context) -> SCNView {
            let view = SCNView()
            view.backgroundColor = .clear
            view.allowsCameraControl = false
            view.antialiasingMode = .multisampling4X
            view.isUserInteractionEnabled = true
            setupScene(for: view, selectedMoon: selectedMoon.name)
            return view
        }
        
        class Coordinator {
            var currentMoon: String? = nil
            var lastOrientationWasLandscape: Bool = UIDevice.current.orientation.isLandscape
            
            func shouldUpdateModel(currentMoon: String?, newOrientationIsLandscape: Bool) -> Bool {
                if currentMoon != self.currentMoon || newOrientationIsLandscape != lastOrientationWasLandscape {
                    self.currentMoon = currentMoon
                    self.lastOrientationWasLandscape = newOrientationIsLandscape
                    return true
                }
                return false
            }
        }
        
        func makeCoordinator() -> Coordinator {
            return Coordinator()
        }
        
        func updateUIView(_ uiView: SCNView, context: Context) {
            if context.coordinator.shouldUpdateModel(currentMoon: selectedMoon.name, newOrientationIsLandscape: deviceOrientation.isLandscape) {
                if let scene = uiView.scene {
                    setupMoonModels(for: scene, selectedMoon: selectedMoon.name)
                    
                    updateSunlightIntensityAndDirection(scene: scene, date: simulationState.date, moonName: selectedMoon.name)
                    
                    updateMarsLightDirection(scene: scene, date: simulationState.date, moonName: selectedMoon.name)
                    
                    context.coordinator.currentMoon = selectedMoon.name
                }
            }
            updateScene(for: uiView, date: simulationState.date, moonName: selectedMoon.name)
        }
        
        private func setupScene(for view: SCNView, selectedMoon: String) {
            guard let scene = SCNScene(named: "Objects/\(selectedMoon).usdz") else { return }
            scene.background.contents = UIColor.clear
            setupCamera(for: scene)
            setupSunlight(for: scene)
            setupMoonModels(for: scene, selectedMoon: selectedMoon)
            setupMarsLight(for: scene)
            
            view.scene = scene
        }
        
        private func setupSunlight(for scene: SCNScene) {
            let sunLight = SCNNode()
            sunLight.name = "sunLight"
            sunLight.light = SCNLight()
            sunLight.light?.type = .directional
            
            sunLight.light?.color = UIColor(hex: "FFFFFF")
            
            sunLight.light?.shadowMode = .deferred
            sunLight.light?.shadowRadius = 8.0
            sunLight.light?.shadowSampleCount = 64
            
            updateSunlightIntensityAndDirection(scene: scene, date: simulationState.date, moonName: selectedMoon.name)
            
            sunLight.light?.shadowMode = .deferred
            sunLight.light?.shadowRadius = 16.0
            sunLight.light?.shadowSampleCount = 128
            
            let ambientLight = SCNNode()
            ambientLight.name = "ambientLight"
            ambientLight.light = SCNLight()
            ambientLight.light?.type = .ambient
            ambientLight.light?.color = UIColor(hex: "413E3D")
            scene.rootNode.addChildNode(ambientLight)
            scene.rootNode.addChildNode(sunLight)
        }
        
        private func setupMoonModels(for scene: SCNScene, selectedMoon: String) {
            let fileName = selectedMoon == "Phobos" ? "Phobos.usdz" : "Deimos.usdz"
            
            guard let moonScene = SCNScene(named: "Objects/\(fileName)") else {
                print("Failed to load the \(fileName) model.")
                return
            }
            
            if let moonNode = moonScene.rootNode.childNodes.first {
                moonNode.name = selectedMoon
                
                scene.rootNode.enumerateChildNodes { (node, _) in
                    if node.name == "Phobos" || node.name == "Deimos" {
                        node.removeFromParentNode()
                    }
                }
                
                scene.rootNode.addChildNode(moonNode)
                
                scene.rootNode.enumerateChildNodes { (node, _) in
                    if node.name == "Phobos" {
                        node.position.y = deviceOrientation.isLandscape ? -2 : 1
                        node.scale = self.deviceOrientation.isLandscape ? SCNVector3(0.7, 0.7, 0.7) : SCNVector3(0.6, 0.6, 0.6)
                    }
                    if node.name == "Deimos" {
                        node.position.y = deviceOrientation.isLandscape ? -2 : 1
                        node.scale = self.deviceOrientation.isLandscape ? SCNVector3(1.1, 1.1, 1.1) : SCNVector3(0.7, 0.7, 0.7)
                    }
                }
                
                let rotationDuration = selectedMoon == "Phobos" ? 7.645 * 3600 : 30.3125 * 3600
                let rotationAction = SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: CGFloat(2 * Double.pi), z: 0, duration: rotationDuration))
                moonNode.runAction(rotationAction)
            }
        }
        
        private func setupMarsLight(for scene: SCNScene) {
            let marsLight = SCNNode()
            marsLight.name = "marsLight"
            marsLight.light = SCNLight()
            marsLight.light?.type = .directional
            marsLight.light?.color = UIColor(hex: "FF5733")
            marsLight.light?.shadowMode = .deferred
            marsLight.light?.shadowRadius = 8.0
            marsLight.light?.shadowSampleCount = 64
            updateMarsLightDirection(scene: scene, date: simulationState.date, moonName: selectedMoon.name)
            
            scene.rootNode.addChildNode(marsLight)
        }
        
        private func updateMarsLightDirection(scene: SCNScene, date: Date, moonName: String) {
            self.globalLoadingState.updateLoading(true)
            
            NASA_API.shared.fetchMarsPositionRelativeToMoon(moonName: moonName, on: date) { result in
                DispatchQueue.main.async {
                    self.globalLoadingState.updateLoading(false)
                }
                
                switch result {
                case .success(let marsPosition):
                    DispatchQueue.main.async {
                        if let marsLightNode = scene.rootNode.childNode(withName: "marsLight", recursively: true) {
                            marsLightNode.position = marsPosition
                            
                            if let light = marsLightNode.light {
                                let distanceFactor: CGFloat = 0.2
                                light.intensity = distanceFactor * 800
                                
                                marsLightNode.eulerAngles.x = Float(25.19.degreesToRadians)
                            }
                        }
                    }
                case .failure(let error):
                    print("Error fetching Mars position:", error.localizedDescription)
                    return
                }
            }
        }
        
        private func setupCamera(for scene: SCNScene) {
            let cameraNode = SCNNode()
            cameraNode.name = "cameraNode"
            cameraNode.camera = SCNCamera()
            cameraNode.position = SCNVector3(x: 0, y: 0, z: 15)
            cameraNode.camera?.fieldOfView = 75
            scene.rootNode.addChildNode(cameraNode)
        }
        
        private func updateSunlightIntensityAndDirection(scene: SCNScene, date: Date, moonName: String) {
            self.globalLoadingState.updateLoading(true)
            
            NASA_API.shared.fetchSunPositionRelativeToMoon(moonName: moonName, on: date) { result in
                DispatchQueue.main.async {
                    self.globalLoadingState.updateLoading(false)
                }
                
                switch result {
                case .success(let sunPosition):
                    DispatchQueue.main.async {
                        if let sunLightNode = scene.rootNode.childNode(withName: "sunLight", recursively: true) {
                            sunLightNode.position = sunPosition
                            
                            if let light = sunLightNode.light {
                                let distanceFactor: CGFloat = 1.0
                                light.intensity = distanceFactor * 1000
                                sunLightNode.eulerAngles.x = Float(25.19.degreesToRadians)
                            }
                        }
                    }
                case .failure(let error):
                    print("Error fetching sun position:", error.localizedDescription)
                }
            }
        }
        
        private func updateScene(for view: SCNView, date: Date, moonName: String) {
            guard let scene = view.scene,
                  let sunLightNode = scene.rootNode.childNode(withName: "sunLight", recursively: true),
                  let moonNode = scene.rootNode.childNode(withName: moonName, recursively: true) else {
                print("Node not found")
                return
            }
            
            let (marsYear, sol) = date.getMarsTime()
            
            DispatchQueue.main.async {
                adjustSunlight(sunLightNode, forSol: sol, andMarsYear: marsYear)
                let rotationRadians = Float(simulationState.cumulativeRotationDegrees).degreesToRadians
                moonNode.eulerAngles.y = rotationRadians
            }
        }
        
        private func calculateMoonRotation(upToDate currentDate: Date, orbitalPeriodHours: Double, from startDate: Date) -> Float {
            let calendar = Calendar.current
            let hoursElapsed = calendar.dateComponents([.hour], from: startDate, to: currentDate).hour ?? 0
            let orbitsCompleted = Double(hoursElapsed) / orbitalPeriodHours
            let rotationRadians = orbitsCompleted * 2 * Double.pi
            return Float(rotationRadians)
        }
        
        private func adjustSunlight(_ sunLightNode: SCNNode, forSol sol: Int, andMarsYear marsYear: Int) {
            let angle = Float(sol % 360) * (.pi / 180)
            let rotateAction = SCNAction.rotateTo(x: 0, y: CGFloat(angle), z: 0, duration: 1.0)
            sunLightNode.runAction(rotateAction)
            let intensityAdjustment = max(0.5, cos(Float(marsYear % 360) * (.pi / 180)))
            let intensityAnimation = CABasicAnimation(keyPath: "light.intensity")
            intensityAnimation.fromValue = sunLightNode.light?.intensity
            intensityAnimation.toValue = intensityAdjustment * 1000
            intensityAnimation.duration = 1.0
            intensityAnimation.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut)
            sunLightNode.addAnimation(intensityAnimation, forKey: "intensityAnimation")
            sunLightNode.light?.intensity = CGFloat(intensityAdjustment * 1000)
        }
    }
}

struct MoonInfoView: View {
    @EnvironmentObject var deviceOrientation: DeviceOrientation
    @ObservedObject var simulationState: SimulationState
    @Binding var moon: Moon
    @State private var marsPosition: PositionVector?
    @State private var moonPosition: PositionVector?
    @State private var distanceFromMars: Double?
    @State private var illuminationPercentage: Double?
    @State private var currentSpeed: Double?
    @State private var moonVelocity: SCNVector3?
    @State private var showData: Bool = false
    @State private var fetchWorkItem: DispatchWorkItem?
    let throttleDelay = 1.0
    
    private let cacheManager = CacheManager.shared
    var calc = Calculator()
    
    var body: some View {
        GeometryReader { geometry in
            VStack {
                HStack(spacing: deviceOrientation.isLandscape ? geometry.size.width / 4 : 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "circle.fill")
                            Text("Radius")
                        }
                        Text(moon.radius ?? "N/A")
                        
                        HStack {
                            Image(systemName: "cube.fill")
                            Text("Density")
                        }
                        Text(moon.density ?? "N/A")
                        
                        HStack {
                            Image(systemName: "arrow.triangle.swap")
                            Text("Orbital Period")
                        }
                        Text(constructOrbitalPeriod(days: moon.orbitalPeriodDays, hours: moon.orbitalPeriodHours))
                    }
                    
                    
                    VStack(alignment: .leading, spacing: 8) {
                        
                        if showData {
                            Text("Current Speed:")
                            Text("\(currentSpeed ?? 0, specifier: "%.2f") km/s")
                            
                            Text("Illumination:")
                            Text("\(illuminationPercentage ?? 0, specifier: "%.2f")%")
                            
                            Text("Distance from Mars:")
                            Text("\(distanceFromMars ?? 0, specifier: "%.2f") km")
                        } else {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Color.white))
                                .padding(64)
                        }
                    }
                }
                .frame(width: geometry.size.width, alignment: .top)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
        }
        .foregroundColor(.white)
        .onAppear {
            simulationState.selectedMoon = moon
            throttleFetchMarsMoonsSunPositions()
        }
        .onChange(of: moon.name) { _, _ in
            simulationState.selectedMoon = moon
            throttleFetchMarsMoonsSunPositions()
        }
        .onChange(of: simulationState.date) { _, _ in
            throttleFetchMarsMoonsSunPositions()
        }
    }
    
    private func constructOrbitalPeriod(days: Double?, hours: Double?) -> String {
        var parts: [String] = []
        if let days = days {
            parts.append("\(days) days")
        }
        if let hours = hours {
            parts.append("\(hours) Hours")
        }
        return parts.joined(separator: " / ")
    }
    
    private func throttleFetchMarsMoonsSunPositions() {
        fetchWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            self.fetchMarsMoonsSunPositions()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + throttleDelay, execute: workItem)
        fetchWorkItem = workItem
    }
    
    private func fetchMarsMoonsSunPositions() {
        guard let moonId = NASA_API.shared.bodyIds[moon.name],
              let marsId = NASA_API.shared.bodyIds["Mars"],
              let sunId = NASA_API.shared.bodyIds["Sun"],
              let dateAtMidnight = simulationState.date.resetTime() else {
            print("Invalid Body Ids or Date Conversion Failed")
            return
        }
        
        let sunCenterId = "10"
        let bodies = [moonId, marsId, sunId]
        showData = false
        fetchBodyPositionsSequentially(bodies: bodies, centerId: sunCenterId, date: dateAtMidnight, positions: [:], completion: { positions in
            guard let marsPosition = positions[marsId],
                  let moonPosition = positions[moonId],
                  let sunPosition = positions[sunId] else {
                print("Failed to fetch all required positions")
                return
            }
            
            self.calc.marsPosition = marsPosition.toSCNVector3()
            self.moonVelocity = SCNVector3(moonPosition.vx, moonPosition.vy, moonPosition.vz)
            self.calc.moonPosition = moonPosition.toSCNVector3()
            self.calc.sunPosition = sunPosition.toSCNVector3()
            self.updateCalculations()
        })
    }
    
    private func fetchBodyPositionsSequentially(bodies: [String], centerId: String, date: Date, positions: [String: PositionVector], index: Int = 0, completion: @escaping ([String: PositionVector]) -> Void) {
        if index >= bodies.count {
            completion(positions)
            return
        }
        
        let bodyId = bodies[index]
        NASA_API.shared.fetchEphemerisDataForBody(bodyId: bodyId, relativeTo: centerId, startDate: date) { result in
            var newPositions = positions
            switch result {
            case .success(let responseString):
                if let positionVector = NASA_API.shared.parsePositionVector(fromApiResponse: responseString) {
                    newPositions[bodyId] = positionVector
                }
            case .failure(let error):
                print("Error fetching position for \(bodyId): \(error.localizedDescription)")
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                self.fetchBodyPositionsSequentially(bodies: bodies, centerId: centerId, date: date, positions: newPositions, index: index + 1, completion: completion)
            }
        }
    }
    
    private func updateCalculations() {
        guard let marsPosition = self.calc.marsPosition, let moonPosition = self.calc.moonPosition else {
            return
        }
        
        self.distanceFromMars = self.calc.calculateDistance(from: marsPosition, to: moonPosition)
        self.currentSpeed = self.calc.calculateSpeed(vx: Double(moonVelocity?.x ?? 0.0), vy: Double(moonVelocity?.y ?? 0.0), vz: Double(moonVelocity?.z ?? 0.0))
        self.illuminationPercentage = self.calc.calculateIlluminationPercentage()
        
        showData = true
    }
    
    class Calculator {
        var marsPosition: SCNVector3?
        var moonPosition: SCNVector3?
        var sunPosition: SCNVector3?
        var distanceFromMars: CGFloat = 0
        var illuminationPercentage: Double = 0
        var currentSpeed: Double = 0
        
        func calculateSpeed(vx: Double, vy: Double, vz: Double) -> Double {
            let speedInAUDay = sqrt(vx * vx + vy * vy + vz * vz)
            let conversionFactor = 1731.46
            self.currentSpeed = speedInAUDay * conversionFactor
            
            return self.currentSpeed
        }
        
        func calculateDistance(from position1: SCNVector3, to position2: SCNVector3) -> Double {
            let dx = position1.x - position2.x
            let dy = position1.y - position2.y
            let dz = position1.z - position2.z
            
            let distance = sqrt(dx*dx + dy*dy + dz*dz)
            let auToKilometers: Double = 149_597_870.7
            return Double(distance) * auToKilometers
        }
        
        func calculateIlluminationPercentage() -> Double {
            guard let marsPosition = marsPosition,
                  let moonPosition = moonPosition,
                  let sunPosition = sunPosition else {
                return 0
            }
            
            let marsToMoonVector = SCNVector3(x: moonPosition.x - marsPosition.x,
                                              y: moonPosition.y - marsPosition.y,
                                              z: moonPosition.z - marsPosition.z)
            let sunToMoonVector = SCNVector3(x: moonPosition.x - sunPosition.x,
                                             y: moonPosition.y - sunPosition.y,
                                             z: moonPosition.z - sunPosition.z)
            
            let dotX = marsToMoonVector.x * sunToMoonVector.x
            let dotY = marsToMoonVector.y * sunToMoonVector.y
            let dotZ = marsToMoonVector.z * sunToMoonVector.z
            let dotProduct = dotX + dotY + dotZ
            
            let marsToMoonDistance = sqrt(pow(marsToMoonVector.x, 2) + pow(marsToMoonVector.y, 2) + pow(marsToMoonVector.z, 2))
            let sunToMoonDistance = sqrt(pow(sunToMoonVector.x, 2) + pow(sunToMoonVector.y, 2) + pow(sunToMoonVector.z, 2))
            
            let cosPhaseAngle = dotProduct / (marsToMoonDistance * sunToMoonDistance)
            let phaseAngle = acos(max(min(cosPhaseAngle, 1.0), -1.0))
            
            let illuminatedFraction = 0.5 * (1 + cos(phaseAngle))
            self.illuminationPercentage = Double(illuminatedFraction * 100)
            
            return self.illuminationPercentage
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
