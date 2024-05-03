//
//  ViewController.swift
//  RGBYUVConversions
//
//  Created by mark lim pak mun on 01/05/2024.
//  Copyright © 2024 Incremental Innovations. All rights reserved.
//

import AppKit
import Accelerate.vImage

class ViewController: NSViewController
{
    var imageView: NSImageView {
        return self.view as! NSImageView
    }

    // Initialise an 8-bit-per-channel XRGB format (Big Endian)
    // On macOS 10.15 or later, the initializer of vImage_CGImageFormat
    // init(cgImage:) can be used if a CGImage object is available.
    var cgImageFormat = vImage_CGImageFormat(
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        colorSpace: nil,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue),
        version: 0,
        decode: nil,
        renderingIntent: .defaultIntent)

    var destinationBuffer = vImage_Buffer()

    // The contents of this object include a 3x3 matrix and clamping info.
    var infoYpCbCrToARGB = vImage_YpCbCrToARGB()

    override func viewDidLoad()
    {
        super.viewDidLoad()
        let err = configureYpCbCrToARGBInfo()
        // bitmapInfo - non-premultiplied RGBA
        guard let cgImage = loadImage()
        else {
            return
        }

        guard let sourceBuffer = vImageBuffer(from: cgImage)
        else {
            return
        }
 
        defer {
            // We don't need the sourceBuffer once the CVPixelBuffer object is created.
            // Since we don't know what's the alignment, we set its value to 1.
            sourceBuffer.data.deallocate(bytes: sourceBuffer.rowBytes*Int(sourceBuffer.height),
                                         alignedTo: 1)
        }
        guard let cvPixelBuffer = cvPixelBuffer(from: sourceBuffer)
        else {
            return
        }

        displayYpCbCrToRGB(pixelBuffer: cvPixelBuffer)
    }

    override var representedObject: Any? {
        didSet {
        }
    }

    deinit {
        // Recover memory on program exit
        defer {
            // A simple free will be enough.
            destinationBuffer.data.deallocate(bytes: destinationBuffer.rowBytes * Int(destinationBuffer.height),
                                              alignedTo: 1)
        }
    }

    // This function expects a biplanar CVPixelBuffer.
    func displayYpCbCrToRGB(pixelBuffer: CVPixelBuffer)
    {
        assert(CVPixelBufferGetPlaneCount(pixelBuffer) == 2, "Pixel buffer should have 2 planes")

        // Lock or the addresses of the planes will be returned as nil.
        CVPixelBufferLockBaseAddress(pixelBuffer,
                                     CVPixelBufferLockFlags.readOnly)

        // Create a vImage_Buffer object from the plane.
        // We shouldn't deallocate lumaBaseAddress because it is managed by the system.
        let lumaBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)
        let lumaWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let lumaHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let lumaRowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        var sourceLumaBuffer = vImage_Buffer(
                data: lumaBaseAddress,
                height: vImagePixelCount(lumaHeight),
                width: vImagePixelCount(lumaWidth),
                rowBytes: lumaRowBytes)
    
        let chromaBaseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)
        let chromaWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
        let chromaHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
        let chromaRowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        var sourceChromaBuffer = vImage_Buffer(
            data: chromaBaseAddress,
            height: vImagePixelCount(chromaHeight),
            width: vImagePixelCount(chromaWidth),
            rowBytes: chromaRowBytes)

        var error = kvImageNoError
        // Remember to free the memory allocated to destinationBuffer
        if destinationBuffer.data == nil {
            error = vImageBuffer_Init(
                &destinationBuffer,
                sourceLumaBuffer.height,
                sourceLumaBuffer.width,
                cgImageFormat.bitsPerPixel,
                vImage_Flags(kvImageNoFlags))

            guard error == kvImageNoError
            else {
                return
            }
        }

        // Convert the Yp and CbCr planes to vImage_Buffer object.
        error = vImageConvert_420Yp8_CbCr8ToARGB8888(
                &sourceLumaBuffer,
                &sourceChromaBuffer,
                &destinationBuffer,
                &infoYpCbCrToARGB,
                nil,
                255,
                vImage_Flags(kvImagePrintDiagnosticsToConsole))

        guard error == kvImageNoError
        else {
            return
        }

        // Create an instance of CGImage from the contents of the vImage_Buffer object.
        let cgImage = vImageCreateCGImageFromBuffer(
            &destinationBuffer,
            &cgImageFormat,     // XRGB
            nil,                // callback
            nil,                // userdata
            vImage_Flags(kvImageNoFlags),
            &error)

        if let cgImage = cgImage,
               error == kvImageNoError {
            DispatchQueue.main.async {
                self.imageView.image = NSImage(cgImage: cgImage.takeUnretainedValue(),
                                               size: NSZeroSize)
            }
        }

        CVPixelBufferUnlockBaseAddress(pixelBuffer,
                                       CVPixelBufferLockFlags.readOnly)
    }

    /*
     Instantiate a CGImage object by loading a graphic image from
     the Resources folder of this demo.
     */
    func loadImage() -> CGImage?
    {
        guard let url = Bundle.main.urlForImageResource("Hibiscus.png")
        else {
            return nil
        }
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil)
        else {
            return nil
        }

        let options = [
            kCGImageSourceShouldCache as String : true,
            kCGImageSourceShouldAllowFloat as String : true
        ] as CFDictionary

        guard let image = CGImageSourceCreateImageAtIndex(imageSource, 0, options)
        else {
            return nil
        }
        // bitmapInfo - non-premultiplied RGBA
        return image
    }

    // Create a vImage_Buffer object from an instance of CGImage.
    // Caller should release the memory allocated to the vImage_Buffer.
    // The pixel format of the returned vImage_Buffer object is XRGB.
    func vImageBuffer(from cgImage: CGImage) -> vImage_Buffer?
    {
        // Initialise an empty vImageBuffer object.
        var buffer = vImage_Buffer()

        // Fill the vImage_Buffer object with the contents of a CGImage object.
        // The memory referenced by buffer.data must be released by the programmer.
        let error = vImageBuffer_InitWithCGImage(
            &buffer,
            &cgImageFormat,     // desired pixel format of vImage_Buffer object
            nil,
            cgImage,
            vImage_Flags(kvImageNoFlags))

        guard error == kvImageNoError
        else {
            return nil
        }

        // The vImageBuffer object is now properly initialised
        return buffer
    }

    // Convert a vImage_Buffer object to a biplanar CVPixelBuffer.
    // The CVPixelBuffer object is not backed by IOSurface
    // If you want the CVPixelBuffer object to be backed by an IOSurface, create
    // a CVPixelBufferPool specifying the `kCVPixelBufferIOSurfacePropertiesKey`.
    func cvPixelBuffer(from buffer: vImage_Buffer) -> CVPixelBuffer?
    {
        let  width = Int(buffer.width)
        let height = Int(buffer.height)

        // We need to release the CVImageFormat Object
        let unmanagedcvFormat = vImageCVImageFormat_Create(
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kvImage_ARGBToYpCbCrMatrix_ITU_R_709_2,
            kCVImageBufferChromaLocation_TopLeft,
            CGColorSpaceCreateDeviceRGB(),
            0)!

        defer {
            // Called when this function cvPixelBuffer(from:) ends.
            unmanagedcvFormat.release()
        }

        let cvFormat = unmanagedcvFormat.takeUnretainedValue()
        var pixelBuffer: CVPixelBuffer?
        // OSType of the CVPixelBuffer object created is '420f'
        // The CVPixelBuffer object will be backed by an IOSurface
        // and is Metal compatible.
        let pixelBufferAttributes = [
            kCVPixelBufferMetalCompatibilityKey as String : true,
            kCVPixelBufferIOSurfacePropertiesKey as String : [String: Any]()
        ] as CFDictionary

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            pixelBufferAttributes,      // can be nil
            &pixelBuffer)

        guard status == kCVReturnSuccess
        else {
            return nil
        }

        var buffer = buffer

        // Copies the contents of the vImage_Buffer object to the CVPixelBuffer object.
        let error = vImageBuffer_CopyToCVPixelBuffer(
            &buffer,
            &cgImageFormat,
            pixelBuffer!,
            cvFormat,
            nil,                // backgroundColor
            vImage_Flags(0))

        guard error == kvImageNoError
        else {
            return nil
        }

        return pixelBuffer
    }

    func configureYpCbCrToARGBInfo() -> vImage_Error
    {
        // video range 8-bit, clamped to video range
        // The bias will be the prebias for YUV -> RGB and postbias for RGB -> YUV
        var pixelRange = vImage_YpCbCrPixelRange(Yp_bias: 16,
                                                 CbCr_bias: 128,
                                                 YpRangeMax: 235,
                                                 CbCrRangeMax: 240,
                                                 YpMax: 235,
                                                 YpMin: 16,
                                                 CbCrMax: 240,
                                                 CbCrMin: 16)

        // Fill the vImage_YpCbCrToARGB struct with correct values
        let error = vImageConvert_YpCbCrToARGB_GenerateConversion(
            kvImage_YpCbCrToARGBMatrix_ITU_R_709_2!,
            &pixelRange,
            &infoYpCbCrToARGB,
            kvImage420Yp8_CbCr8,        // OSType: 420v / 420f
            kvImageARGB8888,            // Any 8-bit, 4-channel interleaved buffer
            vImage_Flags(kvImageNoFlags))

        return error
    }
}

