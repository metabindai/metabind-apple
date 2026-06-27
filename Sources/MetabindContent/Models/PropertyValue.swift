//
// PropertyValue.swift
//
// © 2025 Yap Studios LLC
//

import Foundation

/// Recursive property value structure for content JSON
public indirect enum PropertyValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([PropertyValue])
    case object([String: PropertyValue])
    case contentReference(ContentReference)
    case componentInstance(ComponentInstance)
    case asset(MediaAsset)

    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var array: [PropertyValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var contentReference: ContentReference? {
        if case .contentReference(let value) = self { return value }
        return nil
    }

    public var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var number: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    public var object: [String: PropertyValue]? {
        if case .object(let value) = self { return value }
        return nil
    }
}

public typealias PropertyValueMap = [String: PropertyValue]

public struct ContentReference: Sendable, Equatable {
    public let id: String
    public let content: String  // Referenced content ID
}

public struct ComponentInstance: Sendable, Equatable {
    public let id: String
    public let component: String
    public let arguments: PropertyValueMap
}

public struct MediaAsset: Sendable, Equatable {
    public let id: String
    public let mimeType: String
    public let size: Int
    public let url: String
    public let dimensions: MediaDimensions?
}

public struct MediaDimensions: Sendable, Equatable {
    public let width: Int
    public let height: Int
}
