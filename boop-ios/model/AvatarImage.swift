//
//  AvatarImage.swift
//  boop-ios
//
//

import SwiftUI

/// Transferable image type for PhotosPicker
/// Holds both the SwiftUI Image for display and raw Data for upload
struct AvatarImage: Transferable, Equatable {
    let image: Image
    let data: Data
    
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            guard let image = AvatarImage(data: data) else {
                throw TransferError.importFailed
            }
            return image
        }
    }
}

extension AvatarImage {
    init?(data: Data) {
        guard let uiImage = UIImage(data: data) else {
            return nil
        }
        
        let image = Image(uiImage: uiImage)
        self.init(image: image, data: data)
    }
}

enum TransferError: Error {
    case importFailed
}
