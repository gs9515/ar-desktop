//
//  FilePreviewView.swift
//  ar-desktop
//
//  Created by Gary Smith on 3/30/25.
//

import Foundation
import RealityKit
import SwiftUI
import ARKit
import RealityKitContent
import UIKit
import PDFKit
import _RealityKit_SwiftUI

struct FilePreviewView: View {
    let label: String
    let fileType: String
    let fileLocation: String

    var body: some View {
        VStack(spacing: 0) {
            // ✅ Header
            Text(label)
                .font(.headline)
                .padding()
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
                .overlay(Divider(), alignment: .bottom)

            // ✅ Dynamic content
            Group {
                switch fileType {
                case "pdf":
                    PDFPreview(fileLocation: fileLocation)

                case "photo":
                    ImagePreview(fileLocation: fileLocation)

                case "application":
                    AppPreview(label: label, fileLocation: fileLocation)

                case "file":
                    GenericFilePreview(label: label)

                default:
                    Text("Unknown file type")
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
        }
        .frame(width: 400, height: 500)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(radius: 10)
    }
}


struct PDFPreview: View {
    let fileLocation: String

    var body: some View {
        if let url = Bundle.main.url(forResource: fileLocation, withExtension: nil),
           let document = PDFDocument(url: url) {
            PDFKitRepresentedView(document: document)
        } else {
            Text("Failed to load PDF")
        }
    }
}

struct PDFKitRepresentedView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}



struct ImagePreview: View {
    let fileLocation: String

    var body: some View {
        if let image = UIImage(named: fileLocation) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Text("📷 Failed to load photo")
        }
    }
}



struct AppPreview: View {
    let label: String
    let fileLocation: String

    var body: some View {
        ZStack {
            if let image = UIImage(named: fileLocation) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            } else {
                Rectangle()
                    .fill(primaryColor(for: fileLocation))
                    .ignoresSafeArea()
            }

            VStack {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .foregroundColor(.white)
                    .padding()

                Text("Opening \(label)...")
                    .font(.title2)
                    .foregroundColor(.white)
            }
        }
    }

    func primaryColor(for fileLocation: String) -> Color {
        guard let image = UIImage(named: fileLocation),
              let cgImage = image.cgImage else {
            return Color.blue.opacity(0.9)
        }

        let width = 1
        let height = 1
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixelData = [UInt8](repeating: 0, count: 4)

        guard let context = CGContext(data: &pixelData,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 4,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo) else {
            return Color.blue.opacity(0.9)
        }

        context.draw(cgImage,
                     in: CGRect(x: 0, y: 0, width: width, height: height))

        let red = Double(pixelData[0]) / 255.0
        let green = Double(pixelData[1]) / 255.0
        let blue = Double(pixelData[2]) / 255.0
        let alpha = Double(pixelData[3]) / 255.0

        return Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

struct GenericFilePreview: View {
    let label: String

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .foregroundColor(.gray)

            Text("Preview not available for this file.")
                .font(.callout)
                .foregroundColor(.secondary)

            Text(label)
                .font(.caption)
                .foregroundColor(.primary)
        }
        .padding()
    }
}
