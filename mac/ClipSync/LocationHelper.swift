//
//  LocationHelper.swift
//  ClipSync
//

import Foundation

class LocationHelper {
    static let shared = LocationHelper()
    
    // --- IP Location Detection ---
    func detectRegion(completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://ip-api.com/json/") else {
            completion(nil)
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                print("❌ Location detection failed: \(error?.localizedDescription ?? "Unknown error")")
                completion(nil)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let countryCode = json["countryCode"] as? String {
                    print("📍 Detected Country: \(countryCode)")
                    completion(countryCode)
                } else {
                    completion(nil)
                }
            } catch {
                print("❌ JSON parse error: \(error)")
                completion(nil)
            }
        }
        task.resume()
    }
}
