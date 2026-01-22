import SwiftUI
import CoreImage.CIFilterBuiltins
import Combine
import CryptoKit

class QRCodeGenerator: ObservableObject {
    static let shared = QRCodeGenerator()
    
    @Published var qrImage: NSImage?
    @Published var pairingCode: String = ""
    
    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()
    
    // Hardcoded shared secret (Must match Android side)
    // 32 bytes = 256 bits for AES-256
    private let sharedSecretHex = "5D41402ABC4B2A76B9719D911017C59228B4637452F80776313460C451152033"
    
    // Generate QR code with Encrypted Mac Device ID
    func generateQRCode() {
        let macDeviceId = DeviceManager.shared.getDeviceId()
        
        // Format: JSON string
        let macName = DeviceManager.shared.getMacName()
        let currentRegion = UserDefaults.standard.string(forKey: "server_region") ?? "IN"
        
        let jsonDict: [String: String] = [
            "macId": macDeviceId,
            "deviceName": macName,
            "server": currentRegion // ✅ Tell Phone which server to use
        ]
        
        var plainTextData: Data?
        if let jsonData = try? JSONSerialization.data(withJSONObject: jsonDict) {
            plainTextData = jsonData
        } else {
             // Fallback manual JSON
             let jsonString = "{\"macId\":\"\(macDeviceId)\",\"deviceName\":\"\(macName)\",\"server\":\"\(currentRegion)\"}"
             plainTextData = jsonString.data(using: .utf8)
        }
        
        guard let dataToEncrypt = plainTextData else {
            print("❌ Failed to prepare data for encryption")
            return
        }

        // ENCRYPT
        do {
            let keyData = self.startHexToData(hex: sharedSecretHex)
            let key = SymmetricKey(data: keyData)
            
            // AES-GCM Seal (Generates random Nonce/IV)
            let sealedBox = try AES.GCM.seal(dataToEncrypt, using: key)
            
            // Output format: IV + Ciphertext + Tag (Standard 'combined' format)
            // Base64 encode for QR
            if let combinedData = sealedBox.combined {
                pairingCode = combinedData.base64EncodedString()
                print("🔒 Encrypted Pairing Code (Base64): \(pairingCode)")
            } else {
                print("❌ Failed to combine sealed box")
                return
            }
            
        } catch {
            print("❌ Encryption failed: \(error)")
            // Fallback (for debugging or legacy) - likely shouldn't happen in prod
            pairingCode = String(data: dataToEncrypt, encoding: .utf8) ?? ""
        }
        
        print("🔲 Generating QR Code...")
        
        // Generate QR image
        let data = Data(pairingCode.utf8)
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("L", forKey: "inputCorrectionLevel")
        
        guard let outputImage = filter.outputImage else {
            print("❌ Failed to generate QR code")
            return
        }
        
        // Scale up for clarity (10x larger)
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: transform)
        
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            print("❌ Failed to create CGImage")
            return
        }
        
        qrImage = NSImage(cgImage: cgImage, size: NSSize(
            width: scaledImage.extent.width,
            height: scaledImage.extent.height
        ))
        
        print("✅ QR Code generated successfully!")
    }
    
    // Helper to convert Hex String to Data
    private func startHexToData(hex: String) -> Data {
        var data = Data()
        var temp = ""
        for char in hex {
            temp.append(char)
            if temp.count == 2 {
                if let byte = UInt8(temp, radix: 16) {
                    data.append(byte)
                }
                temp = ""
            }
        }
        return data
    }
    // Fixed Helper naming conflict potentially - ensuring it's private
}

