import AppKit
import AVFoundation
let source = CommandLine.arguments[1]
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let image = NSImage(contentsOfFile: source)!
var rect = NSRect(x: 0, y: 0, width: 1080, height: 1440)
let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
let writer = try AVAssetWriter(outputURL: output, fileType: .mov)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 1080, AVVideoHeightKey: 1440])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 1080, kCVPixelBufferHeightKey as String: 1440])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)
var pixel: CVPixelBuffer?
CVPixelBufferCreate(kCFAllocatorDefault, 1080, 1440, kCVPixelFormatType_32ARGB, [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &pixel)
CVPixelBufferLockBaseAddress(pixel!, [])
let context = CGContext(data: CVPixelBufferGetBaseAddress(pixel!), width: 1080, height: 1440, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixel!), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
context.draw(cg, in: CGRect(x: 0,y: 0,width: 1080,height: 1440))
CVPixelBufferUnlockBaseAddress(pixel!, [])
for index in 0..<90 {
 while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.01) }
 adaptor.append(pixel!, withPresentationTime: CMTime(value: Int64(index), timescale: 30))
}
input.markAsFinished()
let semaphore = DispatchSemaphore(value: 0)
writer.finishWriting { semaphore.signal() }
semaphore.wait()
if writer.status != .completed { fatalError(String(describing: writer.error)) }
