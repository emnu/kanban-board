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
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        
        let contentSize = scrollView.contentSize
        
        let textView = EditorTextView(frame: NSRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height))
        textView.minSize = NSSize(width: 0.0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = .width
        
        textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        
        textView.isRichText = true
        textView.importsGraphics = true // Enable pasting images
        textView.allowsUndo = true
        textView.isEditable = isEditable
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.textColor = .textColor
        textView.font = .systemFont(ofSize: 13)
        
        scrollView.documentView = textView
        
        // Load initial HTML content if not empty
        if !htmlString.isEmpty {
            context.coordinator.setHTML(htmlString, to: textView)
        }
        
        return scrollView
    }
    
    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? EditorTextView else { return }
        
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

// MARK: - 8 Resize Handles Definition
enum ResizeHandle {
    case topLeft
    case topCenter
    case topRight
    case middleLeft
    case middleRight
    case bottomLeft
    case bottomCenter
    case bottomRight
    
    func rect(in cellFrame: NSRect, size: CGFloat) -> NSRect {
        let x: CGFloat
        let y: CGFloat
        
        switch self {
        case .topLeft:
            x = cellFrame.minX - size / 2
            y = cellFrame.minY - size / 2
        case .topCenter:
            x = cellFrame.midX - size / 2
            y = cellFrame.minY - size / 2
        case .topRight:
            x = cellFrame.maxX - size / 2
            y = cellFrame.minY - size / 2
        case .middleLeft:
            x = cellFrame.minX - size / 2
            y = cellFrame.midY - size / 2
        case .middleRight:
            x = cellFrame.maxX - size / 2
            y = cellFrame.midY - size / 2
        case .bottomLeft:
            x = cellFrame.minX - size / 2
            y = cellFrame.maxY - size / 2
        case .bottomCenter:
            x = cellFrame.midX - size / 2
            y = cellFrame.maxY - size / 2
        case .bottomRight:
            x = cellFrame.maxX - size / 2
            y = cellFrame.maxY - size / 2
        }
        
        return NSRect(x: x, y: y, width: size, height: size)
    }
}

// MARK: - EditorTextView Subclass for Handling Intercepts
class EditorTextView: NSTextView {
    
    override func mouseDown(with event: NSEvent) {
        let point = self.convert(event.locationInWindow, from: nil)
        
        // Find if user clicked on an attachment cell frame
        if let hit = hitTestAttachment(at: point) {
            let cellFrame = hit.cellFrame
            let attachment = hit.attachment
            let handleSize: CGFloat = 8
            
            // Check if user clicked on any of the 8 handles
            let handles: [ResizeHandle] = [
                .topLeft, .topCenter, .topRight,
                .middleLeft, .middleRight,
                .bottomLeft, .bottomCenter, .bottomRight
            ]
            
            var clickedHandle: ResizeHandle? = nil
            for handle in handles {
                let handleRect = handle.rect(in: cellFrame, size: handleSize)
                if handleRect.contains(point) {
                    clickedHandle = handle
                    break
                }
            }
            
            // If they clicked a handle, perform the drag resize loop!
            if let handle = clickedHandle {
                performResizeDrag(with: event, for: attachment, cellFrame: cellFrame, handle: handle)
                return // Prevent default text view behavior (no selection change or drag-and-drop!)
            }
        }
        
        // Fallback to default NSTextView mouse down
        super.mouseDown(with: event)
    }
    
    private func hitTestAttachment(at point: NSPoint) -> (attachment: NSTextAttachment, cellFrame: NSRect, charIndex: Int)? {
        guard let layoutManager = self.layoutManager,
              let textContainer = self.textContainer,
              let textStorage = self.textStorage else { return nil }
        
        let length = textStorage.length
        var result: (attachment: NSTextAttachment, cellFrame: NSRect, charIndex: Int)? = nil
        
        textStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: length), options: []) { value, range, stop in
            if let attachment = value as? NSTextAttachment {
                let charIndex = range.location
                let glyphIndex = layoutManager.glyphIndexForCharacter(at: charIndex)
                let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
                let offsetFrame = rect.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y)
                
                // Allow a slight margin for handles that sit outside the frame
                let expandedFrame = offsetFrame.insetBy(dx: -8, dy: -8)
                if expandedFrame.contains(point) {
                    result = (attachment, offsetFrame, charIndex)
                    stop.pointee = true
                }
            }
        }
        return result
    }
    
    private func performResizeDrag(with theEvent: NSEvent, for attachment: NSTextAttachment, cellFrame: NSRect, handle: ResizeHandle) {
        guard let window = self.window else { return }
        
        // Get original image size
        var image: NSImage? = nil
        if let attImage = attachment.image {
            image = attImage
        } else if let fileWrapper = attachment.fileWrapper,
                  let fileData = fileWrapper.regularFileContents {
            image = NSImage(data: fileData)
        } else if let contents = attachment.contents {
            image = NSImage(data: contents)
        }
        
        guard let img = image else { return }
        let originalSize = img.size
        guard originalSize.width > 0, originalSize.height > 0 else { return }
        
        let initialBounds = attachment.bounds
        let aspectRatio = originalSize.width / originalSize.height
        
        var keepTracking = true
        while keepTracking {
            guard let nextEvent = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }
            
            if nextEvent.type == .leftMouseUp {
                keepTracking = false
            }
            
            let currentPoint = self.convert(nextEvent.locationInWindow, from: nil)
            
            var newWidth = initialBounds.width
            var newHeight = initialBounds.height
            
            // Depending on which handle is dragged, recalculate size!
            switch handle {
            case .bottomRight:
                // Dragging bottom-right: changes width and height, maintaining aspect ratio
                newWidth = currentPoint.x - cellFrame.minX
                newWidth = max(40, min(680, newWidth))
                newHeight = newWidth / aspectRatio
                
            case .bottomLeft:
                // Dragging bottom-left: changes width (growing to the left) and height
                newWidth = cellFrame.maxX - currentPoint.x
                newWidth = max(40, min(680, newWidth))
                newHeight = newWidth / aspectRatio
                
            case .topRight:
                // Dragging top-right: changes width and height (growing upwards)
                newWidth = currentPoint.x - cellFrame.minX
                newWidth = max(40, min(680, newWidth))
                newHeight = newWidth / aspectRatio
                
            case .topLeft:
                // Dragging top-left: changes width (growing left) and height (growing up)
                newWidth = cellFrame.maxX - currentPoint.x
                newWidth = max(40, min(680, newWidth))
                newHeight = newWidth / aspectRatio
                
            case .middleRight:
                // Dragging middle-right: adjusts width only (keeps height)
                newWidth = currentPoint.x - cellFrame.minX
                newWidth = max(40, min(680, newWidth))
                
            case .middleLeft:
                // Dragging middle-left: adjusts width only (keeps height)
                newWidth = cellFrame.maxX - currentPoint.x
                newWidth = max(40, min(680, newWidth))
                
            case .bottomCenter:
                // Dragging bottom-center: adjusts height only (keeps width)
                newHeight = currentPoint.y - cellFrame.minY
                newHeight = max(40, newHeight)
                
            case .topCenter:
                // Dragging top-center: adjusts height only (keeps width)
                newHeight = cellFrame.maxY - currentPoint.y
                newHeight = max(40, newHeight)
            }
            
            // Apply new bounds
            attachment.bounds = CGRect(x: 0, y: 0, width: newWidth, height: newHeight)
            
            // Invalidate layout and redraw
            self.layoutManager?.invalidateLayout(forCharacterRange: NSRange(location: 0, length: self.textStorage?.length ?? 0), actualCharacterRange: nil)
            self.needsDisplay = true
        }
        
        // Notify bindings to serialize to HTML and save
        self.didChangeText()
    }
}

// MARK: - Custom NSCell to draw selection borders and 8 handles
class ResizableImageAttachmentCell: NSTextAttachmentCell {
    
    override init(imageCell image: NSImage?) {
        super.init(imageCell: image)
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        super.draw(withFrame: cellFrame, in: controlView)
        
        let handleSize: CGFloat = 8
        let handles: [ResizeHandle] = [
            .topLeft, .topCenter, .topRight,
            .middleLeft, .middleRight,
            .bottomLeft, .bottomCenter, .bottomRight
        ]
        
        // Draw selection border line around the image
        NSColor.systemBlue.setStroke()
        let borderPath = NSBezierPath(rect: cellFrame)
        borderPath.lineWidth = 1.0
        borderPath.stroke()
        
        // Draw 8 handles
        for handle in handles {
            let handleRect = handle.rect(in: cellFrame, size: handleSize)
            
            NSColor.white.set()
            let path = NSBezierPath(rect: handleRect) // Draw square handles!
            path.fill()
            
            NSColor.systemBlue.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }
}

