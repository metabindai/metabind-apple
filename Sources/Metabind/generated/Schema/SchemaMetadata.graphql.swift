// @generated
// This file was automatically generated and should not be edited.

import ApolloAPI

public protocol SelectionSet: ApolloAPI.SelectionSet & ApolloAPI.RootSelectionSet
where Schema == Metabind.SchemaMetadata {}

public protocol InlineFragment: ApolloAPI.SelectionSet & ApolloAPI.InlineFragment
where Schema == Metabind.SchemaMetadata {}

public protocol MutableSelectionSet: ApolloAPI.MutableRootSelectionSet
where Schema == Metabind.SchemaMetadata {}

public protocol MutableInlineFragment: ApolloAPI.MutableSelectionSet & ApolloAPI.InlineFragment
where Schema == Metabind.SchemaMetadata {}

public enum SchemaMetadata: ApolloAPI.SchemaMetadata {
  public static let configuration: any ApolloAPI.SchemaConfiguration.Type = SchemaConfiguration.self

  public static func objectType(forTypename typename: String) -> ApolloAPI.Object? {
    switch typename {
    case "Asset": return Metabind.Objects.Asset
    case "AssetList": return Metabind.Objects.AssetList
    case "Component": return Metabind.Objects.Component
    case "ComponentList": return Metabind.Objects.ComponentList
    case "Content": return Metabind.Objects.Content
    case "ContentList": return Metabind.Objects.ContentList
    case "ContentType": return Metabind.Objects.ContentType
    case "ContentTypeList": return Metabind.Objects.ContentTypeList
    case "ContentUpdate": return Metabind.Objects.ContentUpdate
    case "CursorPagination": return Metabind.Objects.CursorPagination
    case "Package": return Metabind.Objects.Package
    case "PackageDependency": return Metabind.Objects.PackageDependency
    case "PackageList": return Metabind.Objects.PackageList
    case "Query": return Metabind.Objects.Query
    case "ResolvedPackageData": return Metabind.Objects.ResolvedPackageData
    case "ResolvedPackageRef": return Metabind.Objects.ResolvedPackageRef
    case "SavedSearch": return Metabind.Objects.SavedSearch
    case "SavedSearchList": return Metabind.Objects.SavedSearchList
    case "Subscription": return Metabind.Objects.Subscription
    case "Tag": return Metabind.Objects.Tag
    case "TagList": return Metabind.Objects.TagList
    default: return nil
    }
  }
}

public enum Objects {}
public enum Interfaces {}
public enum Unions {}
