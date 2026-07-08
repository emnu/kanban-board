import SwiftUI
import AppKit

public struct RichTextEditor: NSViewRepresentable {
    @Binding var htmlString: String
    @Binding var insertTableTrigger: Bool
    var isEditable: Bool = true
    
    public init(htmlString: Binding<String>, insertTableTrigger: Binding<Bool> = .constant(false), isEditable: Bool = true) {
        self._htmlString = htmlString
        self._insertTableTrigger = insertTableTrigger
        self.isEditable = isEditable
    }
    
    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        
        textView.isRichText = true
        textView.importsGraphics = true // Enable pasting images
        textView.allowsUndo = true
        textView.isEditable = isEditable
        textView.delegate = context.coordinator
        
        // Premium scroll view styling
        scrollView.drawsBackground = false
        textView.drawsBackground = false
        textView.textColor = .textColor
        
        // Font setting
        textView.font = .systemFont(ofSize: 13)
        
        // Load initial HTML content if not empty
        if !htmlString.isEmpty {
            context.coordinator.setHTML(htmlString, to: textView)
        }
        
        return scrollView
    }
    
    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        
        // Update editability dynamically if needed
        if textView.isEditable != isEditable {
            textView.isEditable = isEditable
        }
        
        // Update HTML content if it has changed externally
        let currentHtml = context.coordinator.getHTML(from: textView)
        if !htmlString.isEmpty && currentHtml != htmlString {
            context.coordinator.setHTML(htmlString, to: textView)
        } else if htmlString.isEmpty && !textView.string.isEmpty {
            textView.string = ""
        }
        
        // Check for insert table trigger
        if insertTableTrigger {
            DispatchQueue.main.async {
                self.insertTableTrigger = false
                self.insertTable(into: textView)
            }
        }
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func insertTable(into textView: NSTextView) {
        let tableHTML = """
        <table border="1" style="border-collapse: collapse; width: 100%; margin-top: 8px; margin-bottom: 8px; border: 1px solid #ccc;">
          <thead>
            <tr style="background-color: rgba(120,120,120,0.1);">
              <th style="padding: 6px; border: 1px solid #ccc; font-weight: bold; text-align: left;">Header 1</th>
              <th style="padding: 6px; border: 1px solid #ccc; font-weight: bold; text-align: left;">Header 2</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td style="padding: 6px; border: 1px solid #ccc;">Cell 1</td>
              <td style="padding: 6px; border: 1px solid #ccc;">Cell 2</td>
            </tr>
          </tbody>
        </table>
        """
        
        guard let data = tableHTML.data(using: .utf8),
              let attrTable = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil
              ) else { return }
        
        let range = textView.selectedRange()
        textView.textStorage?.beginEditing()
        textView.insertText(attrTable, replacementRange: range)
        textView.textStorage?.endEditing()
        
        // Trigger delegate update
        textView.didChangeText()
    }
    
    public class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        private var isSettingText = false
        
        init(_ parent: RichTextEditor) {
            self.parent = parent
        }
        
        public func textDidChange(_ notification: Notification) {
            guard !isSettingText, let textView = notification.object as? NSTextView else { return }
            if let textStorage = textView.textStorage {
                scaleAttachmentsToFit(textStorage)
            }
            let html = getHTML(from: textView)
            DispatchQueue.main.async {
                self.parent.htmlString = html
            }
        }
        
        func setHTML(_ html: String, to textView: NSTextView) {
            isSettingText = true
            defer { isSettingText = false }
            
            guard let data = html.data(using: .utf8) else { return }
            
            // NSTextView requires HTML to be loaded on main thread
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ]
            
            if let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
                let mutable = NSMutableAttributedString(attributedString: attributed)
                scaleAttachmentsToFit(mutable)
                textView.textStorage?.setAttributedString(mutable)
                textView.font = .systemFont(ofSize: 13) // Reset to standard system font
            }
        }
        
        private func scaleAttachmentsToFit(_ attrStr: NSAttributedString) {
            guard let mutable = attrStr as? NSMutableAttributedString else { return }
            mutable.enumerateAttribute(.attachment, in: NSRange(location: 0, length: mutable.length), options: []) { value, range, _ in
                if let attachment = value as? NSTextAttachment {
                    var image: NSImage? = nil
                    
                    if let attImage = attachment.image {
                        image = attImage
                    } else if let fileWrapper = attachment.fileWrapper,
                              let fileData = fileWrapper.regularFileContents {
                        image = NSImage(data: fileData)
                    } else if let contents = attachment.contents {
                        image = NSImage(data: contents)
                    }
                    
                    if let image = image {
                        // Assign custom resizable cell if not already set
                        if !(attachment.attachmentCell is ResizableImageAttachmentCell) {
                            let customCell = ResizableImageAttachmentCell(imageCell: image)
                            customCell.attachment = attachment
                            attachment.attachmentCell = customCell
                        }
                        
                        let maxWidth: CGFloat = 680
                        let originalSize = image.size
                        let currentWidth = attachment.bounds.width
                        
                        if currentWidth == 0 {
                            // First time loading: scale if it exceeds maxWidth
                            if originalSize.width > maxWidth {
                                let ratio = maxWidth / originalSize.width
                                attachment.bounds = CGRect(x: 0, y: 0, width: maxWidth, height: originalSize.height * ratio)
                            } else {
                                attachment.bounds = CGRect(x: 0, y: 0, width: originalSize.width, height: originalSize.height)
                            }
                        } else if currentWidth > maxWidth {
                            // Scale down if it exceeds the maximum editor width
                            let ratio = maxWidth / originalSize.width
                            attachment.bounds = CGRect(x: 0, y: 0, width: maxWidth, height: originalSize.height * ratio)
                        }
                    }
                }
            }
        }
        
        
        // MARK: - HTML Generation with Dimension Preservation
        
        func getHTML(from textView: NSTextView) -> String {
            guard let attributedString = textView.textStorage, attributedString.length > 0 else { return "" }
            let range = NSRange(location: 0, length: attributedString.length)
            
            do {
                let documentAttributes: [NSAttributedString.DocumentAttributeKey: Any] = [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ]
                let htmlData = try attributedString.data(from: range, documentAttributes: documentAttributes)
                if let html = String(data: htmlData, encoding: .utf8) {
                    let base64Images = extractImages(from: attributedString)
                    return embedImagesInHTML(html: html, base64Images: base64Images)
                }
            } catch {
                print("Error converting text view text to HTML: \(error)")
            }
            return ""
        }
        
        struct ImageBoundsInfo {
            let base64: String
            let width: CGFloat
            let height: CGFloat
        }
        
        private func extractImages(from attributedString: NSAttributedString) -> [ImageBoundsInfo] {
            var images: [ImageBoundsInfo] = []
            attributedString.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributedString.length), options: []) { value, range, _ in
                if let attachment = value as? NSTextAttachment {
                    var image: NSImage? = nil
                    
                    if let attImage = attachment.image {
                        image = attImage
                    } else if let fileWrapper = attachment.fileWrapper,
                              let fileData = fileWrapper.regularFileContents,
                              let attImage = NSImage(data: fileData) {
                        image = attImage
                    } else if let attData = attachment.contents,
                              let attImage = NSImage(data: attData) {
                        image = attImage
                    }
                    
                    if let image = image,
                       let tiffData = image.tiffRepresentation,
                       let bitmap = NSBitmapImageRep(data: tiffData),
                       let pngData = bitmap.representation(using: .png, properties: [:]) {
                        let base64 = pngData.base64EncodedString()
                        
                        let width = attachment.bounds.width > 0 ? attachment.bounds.width : image.size.width
                        let height = attachment.bounds.height > 0 ? attachment.bounds.height : image.size.height
                        
                        images.append(ImageBoundsInfo(base64: "data:image/png;base64,\(base64)", width: width, height: height))
                    }
                }
            }
            return images
        }
        
        private func embedImagesInHTML(html: String, base64Images: [ImageBoundsInfo]) -> String {
            var resultHtml = html
            let imgPattern = #"(<img[^>]+)src="([^"]+)""#
            guard let imgRegex = try? NSRegularExpression(pattern: imgPattern, options: .caseInsensitive) else {
                return html
            }
            
            let nsString = resultHtml as NSString
            let matches = imgRegex.matches(in: resultHtml, options: [], range: NSRange(location: 0, length: nsString.length))
            
            var imageIndex = 0
            for match in matches.reversed() {
                guard imageIndex < base64Images.count else { break }
                
                let fullRange = match.range(at: 0)
                let prefixRange = match.range(at: 1)
                
                let idx = matches.count - 1 - imageIndex
                let imgInfo = base64Images[idx]
                
                let prefix = nsString.substring(with: prefixRange)
                let replacement = "\(prefix)src=\"\(imgInfo.base64)\" width=\"\(Int(imgInfo.width))\" height=\"\(Int(imgInfo.height))\" style=\"max-width: 100%; height: auto;\""
                
                resultHtml = (resultHtml as NSString).replacingCharacters(in: fullRange, with: replacement)
                imageIndex += 1
            }
            
            return resultHtml
        }
    }
}

// MARK: - Resizable NSTextAttachmentCell for Drag-to-Resize Images
class ResizableImageAttachmentCell: NSTextAttachmentCell {
    
    override init(imageCell image: NSImage?) {
        super.init(imageCell: image)
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override func wantsToTrackMouse() -> Bool {
        return true
    }
    
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        // Draw the original image attachment first
        super.draw(withFrame: cellFrame, in: controlView)
        
        // Draw the circular grab handle in the bottom-right corner
        let handleSize: CGFloat = 10
        let handleRect = NSRect(
            x: cellFrame.maxX - handleSize - 2,
            y: cellFrame.maxY - handleSize - 2,
            width: handleSize,
            height: handleSize
        )
        
        NSColor.white.set()
        let path = NSBezierPath(ovalIn: handleRect)
        path.fill()
        
        NSColor.systemBlue.setStroke()
        path.lineWidth = 2.0
        path.stroke()
    }
    
    override func trackMouse(with theEvent: NSEvent, in cellFrame: NSRect, of controlView: NSView?, untilMouseUp flag: Bool) -> Bool {
        guard let view = controlView as? NSTextView,
              let window = view.window,
              let attachment = self.attachment else { return false }
        
        // Get the active image representation to read original aspect ratio
        guard let image = self.image ?? attachment.image ?? (attachment.contents != nil ? NSImage(data: attachment.contents!) : nil) else {
            return false
        }
        let originalSize = image.size
        guard originalSize.width > 0, originalSize.height > 0 else { return false }
        
        let startPoint = view.convert(theEvent.locationInWindow, from: nil)
        
        // Handle size needs to match the drawing size
        let handleSize: CGFloat = 10
        let handleRect = NSRect(
            x: cellFrame.maxX - handleSize - 2,
            y: cellFrame.maxY - handleSize - 2,
            width: handleSize,
            height: handleSize
        )
        
        // Check if user clicked within the drag handle at the bottom-right corner
        guard handleRect.contains(startPoint) else {
            // Otherwise, fallback to standard text view cell mouse behavior
            return super.trackMouse(with: theEvent, in: cellFrame, of: controlView, untilMouseUp: flag)
        }
        
        // Loop while dragging to dynamically resize
        var keepTracking = true
        while keepTracking {
            guard let nextEvent = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }
            
            if nextEvent.type == .leftMouseUp {
                keepTracking = false
            }
            
            let currentPoint = view.convert(nextEvent.locationInWindow, from: nil)
            
            // Calculate new width relative to the left edge of the cell frame
            var newWidth = currentPoint.x - cellFrame.origin.x
            
            // Enforce minimum width of 40px and maximum editor width of 680px
            newWidth = max(40, min(680, newWidth))
            
            // Maintain exact aspect ratio to prevent squishing
            let ratio = originalSize.height / originalSize.width
            let newHeight = newWidth * ratio
            
            // Apply new bounds
            attachment.bounds = CGRect(x: 0, y: 0, width: newWidth, height: newHeight)
            
            // Force redraw of layout manager and update bounds
            view.layoutManager?.invalidateLayout(forCharacterRange: NSRange(location: 0, length: view.textStorage?.length ?? 0), actualCharacterRange: nil)
            view.needsDisplay = true
        }
        
        // Notify bindings to serialize to HTML and trigger sync
        view.didChangeText()
        return true
    }
}

