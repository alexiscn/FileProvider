//
//  GoogleDriveHelper.swift
//  FilesProvider
//
//  Created by alexiscn on 2021/8/2.
//

import Foundation
#if os(macOS) || os(iOS) || os(tvOS)
import CoreGraphics
#endif

/// Error returned by GoogleDrive server when trying to access or do operations on a file or folder.
public struct FileProviderGoogleDriveError: FileProviderHTTPError {
    public let code: FileProviderHTTPErrorCode
    public let path: String
    public let serverDescription: String?
}

/// Containts path, url and attributes of a GoogleDrive file or resource.
public final class GoogleDriveFileObject: FileObject {
    
    internal convenience init? (jsonStr: String) {
        guard let json = jsonStr.deserializeJSON() else { return nil }
        self.init(json: json)
    }
    
    internal init? (json: [String: Any]) {
        guard let name = json["name"] as? String else { return nil }
        guard let path = json["name"] as? String else { return nil }
        super.init(url: nil, name: name, path: path)
        
        self.id = json["id"] as? String
        let mimeType = json["mimeType"] as? String
        self.type = mimeType == ContentMIMEType.googleFolder.rawValue ? .directory : .regular
        self.size = Int64(json["size"] as? String ?? "-1") ?? -1
        self.modifiedDate = (json["modifiedTime"] as? String).flatMap(Date.init(rfcString:))
        self.creationDate = (json["createdTime"] as? String).flatMap(Date.init(rfcString:))
    }
    
    /// The document identifier is a value assigned by the Box to a file.
    /// This value is used to identify the document regardless of where it is moved on a volume.
    public internal(set) var id: String? {
        get {
            return allValues[.fileResourceIdentifierKey] as? String
        }
        set {
            allValues[.fileResourceIdentifierKey] = newValue
        }
    }
}
