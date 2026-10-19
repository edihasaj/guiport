import Foundation

public enum StreamGeometry {
    public static func dimensions(
        width: Double, height: Double, maxPixels: Int = 8_294_400
    ) throws -> (width: Int, height: Int) {
        guard width.isFinite, height.isFinite, width >= 1, height >= 1 else {
            throw GuiportError(code: "stream_dimensions",
                               message: "Source dimensions must be finite and at least one pixel.")
        }
        guard (1...16_777_216).contains(maxPixels) else {
            throw GuiportError(code: "stream_dimensions",
                               message: "maxPixels must be between 1 and 16777216.")
        }
        let pixelBudget = Double(maxPixels)
        // Division avoids overflowing when a source reports absurd dimensions.
        if width <= pixelBudget / height {
            return (Int(width.rounded(.down)), Int(height.rounded(.down)))
        }
        if width >= height {
            let ratio = height / width
            if ratio <= 1 / pixelBudget { return (maxPixels, 1) }
            let targetHeight = (pixelBudget * ratio).squareRoot()
            return capped(width: targetHeight / ratio, height: targetHeight, maxPixels: maxPixels)
        }
        let ratio = width / height
        if ratio <= 1 / pixelBudget { return (1, maxPixels) }
        let targetWidth = (pixelBudget * ratio).squareRoot()
        return capped(width: targetWidth, height: targetWidth / ratio, maxPixels: maxPixels)
    }

    private static func capped(width: Double, height: Double, maxPixels: Int) -> (width: Int, height: Int) {
        var boundedWidth = min(maxPixels, max(1, Int(width.rounded(.down))))
        var boundedHeight = min(maxPixels, max(1, Int(height.rounded(.down))))
        while boundedWidth > maxPixels / boundedHeight {
            if boundedWidth >= boundedHeight { boundedWidth -= 1 }
            else { boundedHeight -= 1 }
        }
        return (boundedWidth, boundedHeight)
    }
}
