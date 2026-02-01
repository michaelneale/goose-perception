//
// FilesTools.swift
//
// TinyAgent tools for file operations (Spotlight search, PDF).
//

import Foundation
import PDFKit

// MARK: - Open and Get File Path (Spotlight Search)

struct OpenAndGetFilePathTool: TinyAgentTool {
    let name = TinyAgentToolName.openAndGetFilePath
    
    var promptDescription: String {
        """
        open_and_get_file_path(query: str) -> str
         - Search for a file using Spotlight and open it in Finder.
         - query is the filename or search term.
         - Returns the full path of the found file, or an error message if not found.
        """
    }
    
    func execute(arguments: [Any]) async throws -> String {
        guard arguments.count >= 1,
              let query = arguments[0] as? String else {
            throw AppleScriptError.invalidArguments("open_and_get_file_path requires a query argument")
        }
        
        return try await AppleScriptBridge.shared.findFile(query: query)
    }
}

// MARK: - Summarize PDF

struct SummarizePDFTool: TinyAgentTool {
    let name = TinyAgentToolName.summarizePDF
    
    var promptDescription: String {
        """
        summarize_pdf(file_path: str) -> str
         - Extract and summarize the text content from a PDF file.
         - file_path is the full path to the PDF file.
         - Returns the extracted text content (first ~2000 characters).
        """
    }
    
    func execute(arguments: [Any]) async throws -> String {
        guard arguments.count >= 1,
              let filePath = arguments[0] as? String else {
            throw AppleScriptError.invalidArguments("summarize_pdf requires a file_path argument")
        }
        
        let expandedPath = NSString(string: filePath).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)
        
        guard FileManager.default.fileExists(atPath: expandedPath) else {
            throw AppleScriptError.executionFailed("File not found: \(filePath)")
        }
        
        guard let pdfDocument = PDFDocument(url: url) else {
            throw AppleScriptError.executionFailed("Could not open PDF: \(filePath)")
        }
        
        var text = ""
        for pageIndex in 0..<min(pdfDocument.pageCount, 10) {
            if let page = pdfDocument.page(at: pageIndex),
               let pageText = page.string {
                text += pageText + "\n"
            }
            
            // Limit text length
            if text.count > 2000 {
                text = String(text.prefix(2000)) + "..."
                break
            }
        }
        
        if text.isEmpty {
            return "No text content found in PDF"
        }
        
        return text
    }
}
