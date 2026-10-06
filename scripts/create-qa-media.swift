// Generate disposable release QA fixtures into a new, empty directory.
// Usage: swift scripts/create-qa-media.swift /tmp/pruney-qa-fixtures
// Add three short local videos named QA-video-0.mov through QA-video-2.mov separately.
import AppKit
import ImageIO
import UniformTypeIdentifiers
let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let width = 1200, height = 900
var pixels = [UInt8](repeating: 0, count: width * height * 4)
var seed: UInt32 = 19417
for y in 0..<height { for x in 0..<width {
 seed = seed &* 1664525 &+ 1013904223
 let i = (y*width+x)*4
 pixels[i] = UInt8((x*255/width + Int(seed % 45)) % 256)
 pixels[i+1] = UInt8((y*255/height + Int(seed % 45)) % 256)
 pixels[i+2] = UInt8(seed >> 24)
 pixels[i+3] = x < width/4 ? 80 : 255
}}
let provider = CGDataProvider(data: Data(pixels) as CFData)!
let image = CGImage(width: width,height: height,bitsPerComponent: 8,bitsPerPixel: 32,bytesPerRow: width*4,space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),provider: provider,decode: nil,shouldInterpolate: false,intent: .defaultIntent)!
func write(_ name: String, type: UTType, frames: Int = 1) {
 let destination = CGImageDestinationCreateWithURL(folder.appendingPathComponent(name) as CFURL, type.identifier as CFString, frames, nil)!
 if frames > 1 { CGImageDestinationSetProperties(destination,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary) }
 for _ in 0..<frames { CGImageDestinationAddImage(destination,image,[kCGImageDestinationLossyCompressionQuality:0.93,kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:0.15,kCGImagePropertyGIFUnclampedDelayTime:0.15]] as CFDictionary) }
 precondition(CGImageDestinationFinalize(destination))
}
write("QA-transparent.png",type:.png)
write("QA-animation.gif",type:.gif,frames:2)
write("QA-photo.jpg",type:.jpeg)
if (CGImageDestinationCopyTypeIdentifiers() as! [String]).contains(UTType.heic.identifier) { write("QA-photo.heic",type:.heic) }
for i in 0..<54 { try FileManager.default.copyItem(at: folder.appendingPathComponent("QA-photo.jpg"), to:folder.appendingPathComponent(String(format:"QA-photo-%02d.jpg",i))) }
