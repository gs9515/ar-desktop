//
//  FilePreviewView.swift
//  ar-desktop
//
//  Created by Gary Smith on 3/30/25.
//

import SwiftUI
import PDFKit
import UIKit

struct FilePreviewView: View {
    let fileData: FilePreviewData
    
    var body: some View {
        VStack {
            Text(fileData.label)
                .font(.title)
                .padding(.top)
            
            Spacer()
            
            // Display appropriate content based on file type
            Group {
                switch fileData.fileType.lowercased() {
                case "pdf":
                    PDFKitView(url: URL(string: fileData.fileLocation) ?? URL(fileURLWithPath: fileData.fileLocation))
                case "image", "jpg", "png", "jpeg":
                    if let image = UIImage(named: fileData.fileLocation) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Text("Image not found")
                    }
                case "txt", "text":
                    if let textContent = try? String(contentsOfFile: fileData.fileLocation) {
                        ScrollView {
                            Text(textContent)
                                .padding()
                        }
                    } else {
                        Text("Unable to load text content")
                    }
                default:
                    Text("Preview not available for this file type")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Spacer()
            
            Text("Type: \(fileData.fileType)")
                .font(.caption)
                .padding(.bottom)
        }
        .padding()
    }
}

// PDFKit wrapper for PDF files
struct PDFKitView: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.displayMode = .singlePage
        pdfView.autoScales = true
        pdfView.displayDirection = .vertical
        return pdfView
    }
    
    func updateUIView(_ uiView: PDFView, context: Context) {
        if let document = PDFDocument(url: url) {
            uiView.document = document
        }
    }
}
