## Convert an RGB graphc image to a CVPixelBuffer and converting back to an NSImage.

1) Load the graphic and instantiate an instance of CGImage

2) Create a vImage_Buffer object with the returned CGImage of step 1

3) Using the source vImage_Buffer object of step 2, create a biplanar CVPixelBuffer object

4) Convert the CVPixelBuffer object to an instance of CGImage and then to an instance of NSImage.


The function `displayYpCbCrToRGB` is lifted from one of Apple's demos: "Converting Luminance And Chrominance Planes To An ARGBImage"


Note: It is essential to set the pixel format of the CGImage, vImage_Buffer and CVPixelBuffer objects created correctly. The pixel format of a CGImage object can be determined using its `bitmapInfo` property. For a CVPixelBuffer object, the function CVPixelBufferGetPixelFormatType will return its pixel format as an OSType. Currently there is no function or property available to identify the bitmap information of a vImage_Buffer object.


#Requirements:#

XCode 8.x Swift 3.x

macOS 10.12 or later.
