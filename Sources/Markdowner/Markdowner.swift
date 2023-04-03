/*
 *  Highlighter.swift
 *  Copyright 2023, Tony Smith
 *  Copyright 2016, Juan-Pablo Illanes
 *
 *  Licence: MIT
 */


import Foundation
import JavaScriptCore

#if os(OSX)
import AppKit
#endif




/**
    Wrapper class for generating an NSAttributedString from a Markdown string.
 */
open class Markdowner {

    // MARK: - Public Properties
    // When `true`, forces highlighting to finish even if illegal syntax is detected.
    open var ignoreIllegals = false
    open var theme: Theme!

    
    // MARK: - Private Properties
    private let mdjs: JSValue
    private let bundle: Bundle
    private let htmlStart: String = "<"
    private let spanStart: String = "span class=\""
    private let spanStartClose: String = "\">"
    private let spanEnd: String = "/span>"
    private let htmlEscape: NSRegularExpression = try! NSRegularExpression(pattern: "&#?[a-zA-Z0-9]+?;", options: .caseInsensitive)


    // MARK: - Constructor
    
    /**
     The default initialiser.
     
     Returns `nil` on failure to load or evaluate `highlight.min.js`,
     or to load the default theme (`Default`)
    */
    public init?() {
        
        // Get the library's bundle based on how it's
        // being included in the host app
#if SWIFT_PACKAGE
        let bundle = Bundle.module
#else
        let bundle = Bundle(for: Markdowner.self)
#endif
        
        // Load the highlight.js code from the bundle or fail
        guard let mdPath: String = bundle.path(forResource: "markdown-it", ofType: "js") else {
            return nil
        }

        // Check the JavaScript or fail
        let context = JSContext.init()!
        let markdownIt: String = try! String.init(contentsOfFile: mdPath)
        let _ = context.evaluateScript(markdownIt)
        guard let mdjs = context.globalObject.objectForKeyedSubscript("MarkdownIt") else {
            return nil
        }
        
        // Store the results for later
        self.mdjs = mdjs
        self.bundle = bundle
    }

    
    // MARK: - Primary Functions
    
    /**
    Highlight the supplied code in the specified language.
    
    - Parameters:
     - markdownString: The source code to highlight.
     - doFastRender:   Should fast rendering be used? Default: `true`.
     
     - Returns: The highlighted code as an NSAttributedString, or `nil`
    */
    open func render(_ markdownString: String, doFastRender: Bool = true) -> NSAttributedString? {

        // NOTE Will return 'undefined' (trapped below) if it's a unknown language
        let returnValue: JSValue = mdjs.invokeMethod("render", withArguments: [markdownString])
        print(returnValue)
        // Check we got a valid string back - fail if we didn't
        let renderedHTMLValue: JSValue? = returnValue.objectForKeyedSubscript("value")
        guard var renderedHTMLString: String = renderedHTMLValue!.toString() else {
            return nil
        }
        
        // Trap 'undefined' output as this is effectively an error condition
        // and should not be returned as a valid result -- it's actually a fail
        if renderedHTMLString == "undefined" {
            return nil
        }

        // Convert the HTML received from Highlight.js to an NSAttributedString or nil
        var returnAttrString: NSAttributedString? = nil
        
        if doFastRender {
            // Use fast rendering -- the default
            returnAttrString = processHTMLString(renderedHTMLString)!
        } else {
            // Use NSAttributedString's own not-so-fast rendering
            renderedHTMLString = "<style></style>" + renderedHTMLString
            
            let data = renderedHTMLString.data(using: String.Encoding.utf8)!
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ]

            // Execute on main thread
            // NOTE Not sure why, when we don't do this elsewhere
            safeMainSync
            {
                returnAttrString = try? NSMutableAttributedString(data:data, options: options, documentAttributes:nil)
            }
        }

        return returnAttrString
    }

    
    /**
     Generate an NSAttributedString from HTML source.
    
     - Parameters:
        - htmlString: The HTML to be converted.
     
     - Returns: The rendered HTML as an NSAttibutedString, or `nil` if an error occurred.
    */
    private func processHTMLString(_ htmlString: String) -> NSAttributedString? {

        let scanner: Scanner = Scanner(string: htmlString)
        scanner.charactersToBeSkipped = nil
        var scannedString: NSString?
        let resultString: NSMutableAttributedString = NSMutableAttributedString(string: "")
        var propStack: [String] = ["hljs"]

        while !scanner.isAtEnd {
            var ended: Bool = false
            
            let scanned: String? = scanner.scanUpToString(self.htmlStart)
            if scanned != nil {
                ended = scanner.isAtEnd
                if scannedString != nil{
                    scannedString!.appending(scanned!)
                } else {
                    scannedString = scanned as? NSString
                }
            }
            
            if scannedString != nil && scannedString!.length > 0 {
                let attrScannedString: NSAttributedString = self.theme.applyStyleToString(scannedString! as String,
                                                                                          styleList: propStack)
                resultString.append(attrScannedString)

                if ended {
                    continue
                }
            }

            scanner.scanLocation += 1

            let string: NSString = scanner.string as NSString
            let nextChar: String = string.substring(with: NSMakeRange(scanner.scanLocation, 1))
            if nextChar == "s" {
                scanner.scanLocation += (self.spanStart as NSString).length
                scanner.scanUpTo(self.spanStartClose, into: &scannedString)
                scanner.scanLocation += (self.spanStartClose as NSString).length
                propStack.append(scannedString! as String)
            } else if nextChar == "/" {
                scanner.scanLocation += (self.spanEnd as NSString).length
                propStack.removeLast()
            } else {
                let attrScannedString: NSAttributedString = self.theme.applyStyleToString("<", styleList: propStack)
                resultString.append(attrScannedString)
                scanner.scanLocation += 1
            }

            scannedString = nil
        }

        let results: [NSTextCheckingResult] = self.htmlEscape.matches(in: resultString.string,
                                                                      options: [.reportCompletion],
                                                                      range: NSMakeRange(0, resultString.length))
        var localOffset: Int = 0
        for result: NSTextCheckingResult in results {
            let fixedRange: NSRange = NSMakeRange(result.range.location - localOffset, result.range.length)
            let entity: String = (resultString.string as NSString).substring(with: fixedRange)
            if let decodedEntity = HTMLUtils.decode(entity) {
                resultString.replaceCharacters(in: fixedRange, with: String(decodedEntity))
                localOffset += (result.range.length - 1);
            }
        }

        return resultString
    }
    
    
    // MARK:- Utility Functions

    /**
     Execute the supplied block on the main thread.
    */
    private func safeMainSync(_ block: @escaping ()->()) {

        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.sync {
                block()
            }
        }
    }


    
}


/**
 Swap the paragraph style in all of the attributes of
 an NSMutableAttributedString.

- Parameters:
 - paraStyle: The injected NSParagraphStyle.
*/
extension NSMutableAttributedString {
    
    func addParaStyle(with paraStyle: NSParagraphStyle) {
        beginEditing()
        self.enumerateAttribute(.paragraphStyle, in: NSMakeRange(0, self.length)) { (value, range, stop) in
            if let _ = value as? NSParagraphStyle {
                removeAttribute(.paragraphStyle, range: range)
                addAttribute(.paragraphStyle, value: paraStyle, range: range)
            }
        }
        endEditing()
    }
}
