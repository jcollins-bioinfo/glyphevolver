import SwiftUI
import UIKit
import CoreText

struct AdaptiveGlyphView: UIViewRepresentable {
    let glyph: NSAdaptiveImageGlyph
    func makeUIView(context: Context) -> UILabel { UILabel() }
    func updateUIView(_ label: UILabel, context: Context) {
        let font=UIFont.preferredFont(forTextStyle:.largeTitle)
        label.attributedText=NSAttributedString(adaptiveImageGlyph:glyph,attributes:[.font:font])
        label.adjustsFontForContentSizeCategory=true
        label.accessibilityLabel=glyph.contentDescription
    }
}
protocol AdaptiveGlyphRendering {
    func render(glyph: NSAdaptiveImageGlyph, size: CGSize) throws -> UIImage
}
enum GlyphRenderError: Error { case invalidSize, invalidBounds }
struct AdaptiveGlyphRenderer: AdaptiveGlyphRendering {
    func render(glyph: NSAdaptiveImageGlyph, size: CGSize) throws -> UIImage {
        guard size.width.isFinite, size.height.isFinite, size.width>0, size.height>0,
              size.width<=4096, size.height<=4096 else { throw GlyphRenderError.invalidSize }
        let font=CTFontCreateWithName("AppleColorEmoji" as CFString,min(size.width,size.height)*0.8,nil)
        let bounds=CTFontGetTypographicBoundsForAdaptiveImageProvider(font,glyph)
        guard !bounds.isEmpty, bounds.width.isFinite, bounds.height.isFinite else { throw GlyphRenderError.invalidBounds }
        let format=UIGraphicsImageRendererFormat(); format.opaque=false; format.scale=1
        return UIGraphicsImageRenderer(size:size,format:format).image { output in
            let ctx=output.cgContext
            ctx.translateBy(x:0,y:size.height); ctx.scaleBy(x:1,y:-1)
            let scale=min(size.width/bounds.width,size.height/bounds.height)*0.9
            ctx.translateBy(x:(size.width-bounds.width*scale)/2-bounds.minX*scale,
                            y:(size.height-bounds.height*scale)/2-bounds.minY*scale)
            ctx.scaleBy(x:scale,y:scale)
            CTFontDrawImageFromAdaptiveImageProviderAtPoint(font,glyph,.zero,ctx)
        }
    }
}
